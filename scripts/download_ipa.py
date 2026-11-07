"""下載 ios workflow 最新一次成功執行的 ipa 到 dist/（Kevin 用 Sideloadly 安裝）。

用法：python scripts/download_ipa.py [run_id]
GitHub token 用 `git credential fill` 取得，只放在記憶體。
artifact 下載會 302 轉址到儲存區，轉址那一跳不能帶 Authorization。
"""
import io, json, os, re, subprocess, sys, urllib.error, urllib.request, zipfile

REPO = "twenty5088/talkbridge"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def token():
    out = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                         capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r"^password=(.+)$", out, re.M)
    if not m:
        sys.exit("取不到 GitHub token")
    return m.group(1).strip()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def get(url, tok):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def main():
    tok = token()
    if len(sys.argv) > 1:
        run_id = sys.argv[1]
    else:
        runs = get(f"https://api.github.com/repos/{REPO}/actions/workflows/ios.yml/runs?status=success&per_page=1", tok)
        run_id = runs["workflow_runs"][0]["id"]
    arts = get(f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/artifacts", tok)["artifacts"]
    art = next(a for a in arts if a["name"].endswith("-ipa"))
    req = urllib.request.Request(art["archive_download_url"], headers={"Authorization": f"Bearer {tok}"})
    try:
        urllib.request.build_opener(NoRedirect).open(req)
        sys.exit("沒有轉址，無法下載")
    except urllib.error.HTTPError as e:
        if e.code not in (301, 302, 303, 307, 308):
            raise
        data = urllib.request.urlopen(e.headers["Location"]).read()
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in z.namelist():
            if name.endswith(".ipa"):
                target = os.path.join(ROOT, "dist", os.path.basename(name))
                with open(target, "wb") as f:
                    f.write(z.read(name))
                print(f"{target}  {os.path.getsize(target)} bytes  (run {run_id}, artifact {art['name']})")


if __name__ == "__main__":
    main()
