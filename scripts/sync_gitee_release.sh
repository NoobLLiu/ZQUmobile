#!/usr/bin/env bash
# 把 GitHub 的 latest Release（3 个 APK + version.json）镜像到 Gitee 同名 Release。
# 只搬 Release 与构建产物，不碰 git 代码；Gitee 侧永远只保留一个 latest。
set -euo pipefail

: "${GITEE_TOKEN:?缺少 GITEE_TOKEN}"
: "${GH_TOKEN:?缺少 GH_TOKEN}"

GITEE_OWNER="${GITEE_OWNER:-NoobLLiu}"
GITEE_REPO="${GITEE_REPO:-ZQUmobile}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-NoobLLiu/ZQUmobile}"
TARGET_COMMITISH="${GITEE_TARGET_COMMITISH:-master}"
TAG="latest"
WORK_DIR="${RUNNER_TEMP:-/tmp}/zsy-gitee-sync"
API="https://gitee.com/api/v5/repos/${GITEE_OWNER}/${GITEE_REPO}"
BASE_URL="https://gitee.com/${GITEE_OWNER}/${GITEE_REPO}/releases/download/${TAG}"
RELEASE_PAGE="https://gitee.com/${GITEE_OWNER}/${GITEE_REPO}/releases/tag/${TAG}"
UPSTREAM="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${TAG}"

api() { curl -sS --show-error --fail-with-body --max-time 180 "$@"; }
log() { echo ":: $*"; }

mkdir -p "$WORK_DIR"

log "拉取 GitHub ${GITHUB_REPOSITORY} 的 ${TAG} 产物"
gh release download "$TAG" --repo "$GITHUB_REPOSITORY" --dir "$WORK_DIR" --clobber

META="$WORK_DIR/version.json"
[ -f "$META" ] || { echo "::error::GitHub ${TAG} 里没有 version.json，请先跑一次 CI 构建"; exit 1; }

# version.json 是自动更新的数据源：把下载直链改写成 Gitee 地址，保留上游地址可回退。
eval "$(python3 - "$META" "$BASE_URL" "$RELEASE_PAGE" "$UPSTREAM" <<'PY'
import json, os, shlex, sys

meta, base, page, upstream = sys.argv[1:5]
with open(meta, encoding="utf-8") as f:
    d = json.load(f)

for a in d.get("assets", []):
    a["upstreamUrl"] = a["url"]
    a["url"] = base + "/" + a["name"]
d["mirror"] = "gitee"
d["releasePage"] = page
d["upstream"] = upstream
d["versionJsonUrl"] = base + "/version.json"

with open(meta, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
with open(os.path.join(os.path.dirname(meta), "apks.txt"), "w", encoding="utf-8") as f:
    for a in d.get("assets", []):
        if a["name"].endswith(".apk"):
            f.write(a["name"] + "\n")

for key, value in [
    ("FULL_VERSION", d["fullVersion"]),
    ("VERSION", d["version"]),
    ("BUILD", str(d["versionCode"])),
    ("BUILD_TIME", d["buildTime"]),
    ("GIT_SHA", d["gitSha"]),
    ("RELEASE_NOTES", d.get("releaseNotes", "")),
]:
    print("%s=%s" % (key, shlex.quote(str(value))))
PY
)"

mapfile -t APKS < "$WORK_DIR/apks.txt"
[ "${#APKS[@]}" -eq 3 ] || { echo "::error::version.json 里应有 3 个 APK，实际 ${#APKS[@]} 个"; exit 1; }
for name in "${APKS[@]}"; do
  [ -f "$WORK_DIR/$name" ] || { echo "::error::缺少产物 $name"; exit 1; }
done

TITLE="掌上砚园 ${FULL_VERSION}"
LINKS=""
for name in "${APKS[@]}"; do
  LINKS="${LINKS}- [${name}](${BASE_URL}/${name})"$'\n'
done
BODY=$(cat <<EOF
## 掌上砚园 ${FULL_VERSION}

- 版本号：\`${VERSION}\`　versionCode：\`${BUILD}\`
- 构建时间：\`${BUILD_TIME}\`
- 提交：\`${GIT_SHA}\`
- 更新说明：${RELEASE_NOTES}

### 下载（国内直链）

${LINKS}- [version.json（自动更新数据源）](${BASE_URL}/version.json)

> 本仓库只镜像安装包与版本信息，不含源码。上游：${UPSTREAM}
EOF
)

# 整删整建：Gitee 不会自动清同名附件，删掉重建才不会堆历史 APK。
# 实测 DELETE 返回 204，且同名 tag latest 可以立即重建。
EXISTING=$(api "$API/releases?access_token=${GITEE_TOKEN}&per_page=100" \
  | python3 -c "import sys,json; print(' '.join(str(r['id']) for r in json.load(sys.stdin) if r.get('tag_name')=='latest'))")
for rid in $EXISTING; do
  log "删除旧的 Gitee latest Release (${rid})"
  api -X DELETE "$API/releases/${rid}?access_token=${GITEE_TOKEN}" -o /dev/null
done

log "创建 Gitee Release：${TITLE}"
CREATED=$(api -X POST "$API/releases" \
  --data-urlencode "access_token=${GITEE_TOKEN}" \
  --data-urlencode "tag_name=${TAG}" \
  --data-urlencode "name=${TITLE}" \
  --data-urlencode "body=${BODY}" \
  --data-urlencode "target_commitish=${TARGET_COMMITISH}" \
  --data-urlencode "prerelease=false")
RID=$(echo "$CREATED" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
[ -n "$RID" ] || { echo "::error::创建 Gitee Release 失败：$CREATED"; exit 1; }

for name in "${APKS[@]}" version.json; do
  log "上传 ${name}"
  api -X POST "$API/releases/${RID}/attach_files?access_token=${GITEE_TOKEN}" \
    -F "file=@${WORK_DIR}/${name}" -o /dev/null
done

# 校验：Gitee 会自动追加 latest.zip / latest.tar.gz，只核对我们要的 4 个。
GOT=$(api "$API/releases/${RID}?access_token=${GITEE_TOKEN}" \
  | python3 -c "import sys,json; print('\n'.join(a['name'] for a in json.load(sys.stdin).get('assets',[])))")
for name in "${APKS[@]}" version.json; do
  echo "$GOT" | grep -Fxq "$name" || { echo "::error::Gitee 缺少附件 ${name}；实际：${GOT}"; exit 1; }
done

log "完成：${RELEASE_PAGE}"
{
  echo "### Gitee Release 已同步"
  echo ""
  echo "- 版本：\`${FULL_VERSION}\`（versionCode \`${BUILD}\`），构建时间 \`${BUILD_TIME}\`"
  echo "- Release 页面：${RELEASE_PAGE}"
  echo "- 自动更新数据源：${BASE_URL}/version.json"
  echo ""
  for name in "${APKS[@]}"; do
    echo "- ${BASE_URL}/${name}"
  done
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
