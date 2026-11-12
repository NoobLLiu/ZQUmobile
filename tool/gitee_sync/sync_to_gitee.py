#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""掌上砚园：把 GitHub latest Release 与快递站数据一键同步到 Gitee。

双击同目录的「一键同步到Gitee.bat」即可运行（Release + 数据）；
只想更新快递站数据时双击「仅同步快递站数据.bat」，或命令行加 --data-only。
也可用 GITEE_TOKEN 环境变量提供令牌（CI 用），无需本机配置文件。
只用 Python 标准库 + 系统自带的 curl，不装任何依赖。
"""

import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import traceback

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except Exception:
        pass

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(BASE_DIR, "cache")
CONFIG_PATH = os.path.join(BASE_DIR, "_local_config.json")
LOG_PATH = os.path.join(BASE_DIR, "sync.log")

OWNER = "NoobLLiu"
REPO = "ZQUmobile"
GITHUB_REPO = "NoobLLiu/ZQUmobile"
TAG = "latest"
TARGET_COMMITISH = "master"

API = f"https://gitee.com/api/v5/repos/{OWNER}/{REPO}"
# 不走 github.com：本机代理对它的 CONNECT 会 502，api.github.com 通。
GH_API = f"https://api.github.com/repos/{GITHUB_REPO}"
GITEE_BASE = f"https://gitee.com/{OWNER}/{REPO}/releases/download/{TAG}"
RELEASE_PAGE = f"https://gitee.com/{OWNER}/{REPO}/releases/tag/{TAG}"
UPSTREAM = f"https://github.com/{GITHUB_REPO}/releases/tag/{TAG}"

# 快递站数据：仓库里的普通文件，不放 Release 附件（改数据不需要重建 Release）。
GITEE_BRANCH = "master"
DATA_REL_PATH = "data/express_stations.json"
DATA_LOCAL_PATH = os.path.normpath(
    os.path.join(BASE_DIR, "..", "..", DATA_REL_PATH)
)
GITEE_CONTENTS = f"{API}/contents/{DATA_REL_PATH}"
GITEE_DATA_RAW = (
    f"https://gitee.com/{OWNER}/{REPO}/raw/{GITEE_BRANCH}/{DATA_REL_PATH}"
)


def log(msg=""):
    print(msg, flush=True)


def curl_path():
    found = shutil.which("curl")
    if not found:
        raise RuntimeError("找不到 curl.exe（Windows 10 1803 之后系统自带）")
    return found


def api(args, timeout=180):
    cmd = [curl_path(), "-sS", "--show-error", "--fail-with-body",
           "--max-time", str(timeout)] + args
    done = subprocess.run(cmd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    if done.returncode:
        detail = (done.stderr or done.stdout or "").strip()[:300]
        raise RuntimeError(f"请求 Gitee 失败：{detail}")
    return done.stdout


def api_with_status(args, timeout=180):
    """同 api()，但保留 HTTP 状态码（404 也算正常结果，用来判断文件是否存在）。"""
    cmd = [curl_path(), "-sS", "--show-error", "--max-time", str(timeout),
           "-w", "\n__ZSY_HTTP_STATUS__%{http_code}"] + args
    done = subprocess.run(cmd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    if done.returncode:
        detail = (done.stderr or done.stdout or "").strip()[:300]
        raise RuntimeError(f"请求 Gitee 失败：{detail}")
    body, sep, status = done.stdout.rpartition("__ZSY_HTTP_STATUS__")
    if not sep:
        raise RuntimeError("读取 Gitee 响应状态码失败")
    return int(status.strip()), body


def _normalize_bytes(raw):
    """忽略 CRLF / 末尾空行差异，避免 Gitee 存储格式变化导致每次都重写。"""
    return raw.replace(b"\r\n", b"\n").strip()


def sync_data_file(token):
    """把仓库根的快递站 JSON 同步到 Gitee 仓库同路径；内容相同则跳过。

    走 Gitee Contents API 建/改文件，不碰 Release：数据改一次即可生效，
    不用删建 latest、不用重传 3 个 APK。返回是否真的写入了。
    """
    if not os.path.isfile(DATA_LOCAL_PATH):
        raise RuntimeError(f"找不到快递站数据文件：{DATA_LOCAL_PATH}")
    with open(DATA_LOCAL_PATH, "rb") as f:
        local = f.read()
    try:
        parsed = json.loads(local.decode("utf-8"))
        revision = parsed["revision"]
        if not isinstance(parsed.get("groups"), list) or not parsed["groups"]:
            raise ValueError("groups 为空")
    except Exception as exc:
        raise RuntimeError(f"快递站数据不是合法的数据包：{exc}")

    # 顺手提醒：出厂初始包是不是也跟着更新了（CI 会重新生成，本机靠 flutter test 兜底）。
    bundled_path = os.path.normpath(
        os.path.join(BASE_DIR, "..", "..", "app", "assets", "express_stations.json")
    )
    if os.path.isfile(bundled_path):
        with open(bundled_path, "rb") as f:
            bundled = f.read()
        if _normalize_bytes(bundled) != _normalize_bytes(local):
            log("  [提醒] app/assets/express_stations.json 与数据源不一致，")
            log("         请运行 dart tool/gen_express_stations.dart 更新出厂包（CI 会自动跑）。")

    status, body = api_with_status(
        [f"{GITEE_CONTENTS}?access_token={token}&ref={GITEE_BRANCH}"]
    )
    remote = None
    if status == 404:
        pass
    elif 200 <= status < 300:
        # Gitee 对不存在的路径返回 200 + []（空数组），而不是 404。
        try:
            decoded = json.loads(body)
        except Exception:
            decoded = None
        remote = decoded if isinstance(decoded, dict) else None
    else:
        raise RuntimeError(
            f"读取 Gitee 数据文件失败（HTTP {status}）：{body[:200]}"
        )

    verb = "POST"
    extra = []
    if remote is not None:
        try:
            remote_bytes = base64.b64decode(remote.get("content", ""))
        except Exception:
            remote_bytes = b""
        if _normalize_bytes(remote_bytes) == _normalize_bytes(local):
            log(f"  快递站数据已是最新（r{revision}），无需同步")
            return False
        verb = "PUT"
        sha = remote.get("sha", "")
        if not sha:
            raise RuntimeError("Gitee 返回的数据文件缺少 sha，无法更新")
        extra = ["--data-urlencode", f"sha={sha}"]

    # 统一按 LF 上传，避免 Windows 的 CRLF 把 Gitee 文件反复改写成另一种行尾。
    payload = base64.b64encode(local.replace(b"\r\n", b"\n")).decode("ascii")
    status, body = api_with_status(
        ["-X", verb, GITEE_CONTENTS,
         "--data-urlencode", f"access_token={token}",
         "--data-urlencode", f"content={payload}",
         "--data-urlencode", f"message=chore(data): sync express stations r{revision}",
         "--data-urlencode", f"branch={GITEE_BRANCH}"] + extra
    )
    if not 200 <= status < 300:
        raise RuntimeError(
            f"写入 Gitee 数据文件失败（HTTP {status}）：{body[:300]}"
        )
    log(f"  已{'更新' if verb == 'PUT' else '创建'} Gitee 数据文件（r{revision}）")
    log(f"  App 热更新地址：{GITEE_DATA_RAW}")
    return True


def http_get_json(url):
    cmd = [curl_path(), "-sS", "--show-error", "--fail-with-body",
           "--max-time", "120", "-L", url]
    done = subprocess.run(cmd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    if done.returncode:
        detail = (done.stderr or done.stdout or "").strip()[:300]
        raise RuntimeError(f"读取 GitHub Release 信息失败：{detail}")
    return json.loads(done.stdout)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def download_asset(asset_id, path, sha=None):
    name = os.path.basename(path)
    # 国内从 GitHub 拉 50MB 常要十几分钟，命中缓存就别再拉一次。
    if sha and os.path.isfile(path) and sha256_file(path) == sha:
        log(f"  缓存命中 {name}")
        return
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = path + ".part"
    url = f"{GH_API}/releases/assets/{asset_id}"
    for _ in range(2):
        resume = os.path.isfile(tmp) and os.path.getsize(tmp) > 0
        cmd = [curl_path(), "-L", "--fail", "--retry", "3",
               "--retry-all-errors", "--retry-delay", "3",
               "--connect-timeout", "20", "--max-time", "1800",
               "-H", "Accept: application/octet-stream"]
        if resume:
            cmd += ["-C", "-"]
            log(f"  续传 {name}（已有 {os.path.getsize(tmp) / 1048576:.1f} MB）")
        else:
            log(f"  下载 {name} ...（首次约 50MB，可能要十几分钟）")
        cmd += ["-o", tmp, url]
        done = subprocess.run(cmd)
        if done.returncode == 0 and os.path.isfile(tmp):
            if not sha or sha256_file(tmp) == sha:
                os.replace(tmp, path)
                log(f"  完成 {name}  {os.path.getsize(path) / 1048576:.1f} MB")
                return
        if os.path.isfile(tmp):
            os.remove(tmp)
    raise RuntimeError(f"下载失败或 sha256 校验不通过：{name}")


def upload(token, rid, path, name):
    started = time.time()
    cmd = [curl_path(), "-sS", "--show-error", "--fail-with-body",
           "--max-time", "600", "-X", "POST",
           f"{API}/releases/{rid}/attach_files?access_token={token}",
           "-F", f"file=@{path};filename={name}", "-o", os.devnull]
    done = subprocess.run(cmd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    if done.returncode:
        detail = (done.stderr or done.stdout or "").strip()[:300]
        raise RuntimeError(f"上传 {name} 失败：{detail}")
    log(f"  上传完成 {name}  {time.time() - started:.1f}s")


def load_token():
    # CI 里没有本机配置文件，直接用环境变量注入的令牌。
    env_token = os.environ.get("GITEE_TOKEN", "").strip()
    if env_token:
        return env_token
    if os.path.isfile(CONFIG_PATH):
        with open(CONFIG_PATH, encoding="utf-8") as f:
            token = json.load(f).get("gitee_token", "").strip()
        if token:
            return token
    import getpass
    log("首次使用：请输入 Gitee 账号级私人令牌（输入不显示，只保存在本机）")
    token = getpass.getpass("令牌: ").strip()
    if not token:
        raise RuntimeError("未输入令牌，已取消")
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump({"gitee_token": token}, f, ensure_ascii=False, indent=2)
    log(f"已保存到 {CONFIG_PATH}")
    return token


def main():
    started = time.time()
    data_only = "--data-only" in sys.argv[1:]
    log("=" * 58)
    log("  掌上砚园 · 同步到 Gitee" +
        ("（仅快递站数据）" if data_only else "（Release + 快递站数据）"))
    log("=" * 58)
    curl_path()
    token = load_token()

    # 快递站数据放仓库文件，独立于 Release；幂等，内容没变就跳过。
    log("\n[1/1] 同步快递站数据到 Gitee 仓库" if data_only
        else "\n[1/6] 同步快递站数据到 Gitee 仓库")
    sync_data_file(token)
    if data_only:
        log("\n" + "=" * 58)
        log(f"  数据同步完成，用时 {time.time() - started:.1f} 秒")
        log("=" * 58)
        log(f"  热更新地址：{GITEE_DATA_RAW}")
        log("  Release 未改动（数据只写仓库文件）。\n")
        return

    log("\n[2/6] 读取 GitHub 版本清单")
    release_info = http_get_json(f"{GH_API}/releases/tags/{TAG}")
    asset_ids = {a["name"]: a["id"] for a in release_info.get("assets", [])}
    if "version.json" not in asset_ids:
        raise RuntimeError("GitHub latest 里没有 version.json，请先跑一次 CI 构建")
    raw_meta = os.path.join(CACHE_DIR, "version.json")
    download_asset(asset_ids["version.json"], raw_meta)
    with open(raw_meta, encoding="utf-8") as f:
        meta = json.load(f)
    apks = [a for a in meta.get("assets", []) if a["name"].endswith(".apk")]
    if len(apks) != 3:
        raise RuntimeError(f"版本清单里应有 3 个 APK，实际 {len(apks)} 个")
    full = meta["fullVersion"]
    log(f"  版本 {full}（versionCode {meta['versionCode']}，{meta['buildTime']}）")

    log("\n[3/6] 下载安装包（已有且 sha256 一致则跳过）")
    for a in apks:
        if a["name"] not in asset_ids:
            raise RuntimeError(f"GitHub Release 里缺少 {a['name']}")
        download_asset(asset_ids[a["name"]],
                       os.path.join(CACHE_DIR, a["name"]),
                       sha=a.get("sha256"))

    log("\n[4/6] 生成 Gitee 版 version.json")
    gitee_meta = json.loads(json.dumps(meta))
    for a in gitee_meta.get("assets", []):
        a["upstreamUrl"] = a["url"]
        a["url"] = f"{GITEE_BASE}/{a['name']}"
    gitee_meta.update({
        "mirror": "gitee",
        "releasePage": RELEASE_PAGE,
        "upstream": UPSTREAM,
        "versionJsonUrl": f"{GITEE_BASE}/version.json",
    })
    gitee_meta_path = os.path.join(CACHE_DIR, "version.gitee.json")
    with open(gitee_meta_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(gitee_meta, f, ensure_ascii=False, indent=2)
        f.write("\n")

    title = f"掌上砚园 {full}"
    links = "".join(f"- [{a['name']}]({GITEE_BASE}/{a['name']})\n" for a in apks)
    body = (
        f"## 掌上砚园 {full}\n\n"
        f"- 版本号：`{meta['version']}`　versionCode：`{meta['versionCode']}`\n"
        f"- 构建时间：`{meta['buildTime']}`\n"
        f"- 提交：`{meta['gitSha']}`\n"
        f"- 更新说明：{meta.get('releaseNotes', '')}\n\n"
        f"### 下载（国内直链）\n\n{links}"
        f"- [version.json（自动更新数据源）]({GITEE_BASE}/version.json)\n\n"
        f"> 本仓库只镜像安装包与版本信息，不含源码。上游：{UPSTREAM}\n"
    )

    log("\n[5/6] 重建 Gitee latest Release")
    releases = json.loads(api([f"{API}/releases?access_token={token}&per_page=100"]))
    for rel in releases:
        if rel.get("tag_name") == TAG:
            log(f"  删除旧 Release {rel['id']}")
            api(["-X", "DELETE", f"{API}/releases/{rel['id']}?access_token={token}"])
    created = json.loads(api([
        "-X", "POST", f"{API}/releases",
        "--data-urlencode", f"access_token={token}",
        "--data-urlencode", f"tag_name={TAG}",
        "--data-urlencode", f"name={title}",
        "--data-urlencode", f"body={body}",
        "--data-urlencode", f"target_commitish={TARGET_COMMITISH}",
        "--data-urlencode", "prerelease=false",
    ]))
    rid = created["id"]
    log(f"  已创建：{title}（id {rid}）")

    log("\n[6/6] 上传附件")
    upload(token, rid, gitee_meta_path, "version.json")
    for a in apks:
        upload(token, rid, os.path.join(CACHE_DIR, a["name"]), a["name"])

    detail = json.loads(api([f"{API}/releases/{rid}?access_token={token}"]))
    have = {a["name"] for a in detail.get("assets", [])}
    want = {"version.json"} | {a["name"] for a in apks}
    missing = want - have
    if missing:
        raise RuntimeError("Gitee 缺少附件：" + ", ".join(sorted(missing)))

    log("\n" + "=" * 58)
    log(f"  同步完成，用时 {time.time() - started:.1f} 秒")
    log("=" * 58)
    log(f"  版本：{full}（versionCode {meta['versionCode']}）")
    log(f"  页面：{RELEASE_PAGE}")
    log(f"  更新源：{GITEE_BASE}/version.json")
    for a in apks:
        log(f"  {GITEE_BASE}/{a['name']}")
    log("")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("\n已取消")
        sys.exit(1)
    except Exception as exc:
        try:
            with open(LOG_PATH, "w", encoding="utf-8") as f:
                f.write(traceback.format_exc())
        except Exception:
            pass
        log(f"\n[失败] {exc}")
        log(f"详细日志：{LOG_PATH}")
        sys.exit(1)
