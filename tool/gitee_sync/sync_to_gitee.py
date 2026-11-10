#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""掌上砚园：把 GitHub latest Release 一键同步到 Gitee 国内镜像。

双击同目录的「一键同步到Gitee.bat」即可运行。
只用 Python 标准库 + Windows 自带的 curl.exe，不装任何依赖。
"""

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
    log("=" * 58)
    log("  掌上砚园 · GitHub Release -> Gitee 一键同步")
    log("=" * 58)
    curl_path()
    token = load_token()

    log("\n[1/5] 读取 GitHub 版本清单")
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

    log("\n[2/5] 下载安装包（已有且 sha256 一致则跳过）")
    for a in apks:
        if a["name"] not in asset_ids:
            raise RuntimeError(f"GitHub Release 里缺少 {a['name']}")
        download_asset(asset_ids[a["name"]],
                       os.path.join(CACHE_DIR, a["name"]),
                       sha=a.get("sha256"))

    log("\n[3/5] 生成 Gitee 版 version.json")
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

    log("\n[4/5] 重建 Gitee latest Release")
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

    log("\n[5/5] 上传附件")
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
