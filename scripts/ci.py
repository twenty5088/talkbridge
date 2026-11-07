"""推送目前 HEAD，等待 GitHub Actions 結果（Claude 開發用）。

- core：.github/workflows/core.yml（Linux 單元測試）
- ios ：.github/workflows/ios.yml（macOS 完整流程；推送沒觸發時改用 workflow_dispatch）
等待期間會更新 docs/superpowers/progress.md 的 last_active，讓自動續做排程知道有人在做。
完整 log 存在 .ci/last-<kind>.log（不進 git）。失敗時 exit 1。
"""
import datetime, json, os, re, subprocess, sys, time, urllib.error, urllib.request

REPO = "twenty5088/talkbridge"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = {"core": "core.yml", "ios": "ios.yml"}
TIMEOUT_MIN = {"core": 25, "ios": 60}


def token():
    out = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                         capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r"^password=(.+)$", out, re.M)
    if not m:
        sys.exit("取不到 GitHub token（git credential fill）")
    return m.group(1).strip()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def api(path, tok, method="GET", body=None, raw=False):
    req = urllib.request.Request(path if path.startswith("http") else f"https://api.github.com/repos/{REPO}{path}",
                                 method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {tok}", "Accept": "application/vnd.github+json"})
    if raw:  # 下載 log：302 轉址那一跳不能帶 Authorization
        try:
            urllib.request.build_opener(NoRedirect).open(req)
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 303, 307, 308):
                return urllib.request.urlopen(e.headers["Location"]).read().decode("utf-8", "replace")
            raise
        return ""
    with urllib.request.urlopen(req) as r:
        data = r.read()
        return json.loads(data) if data else {}


def heartbeat():
    p = os.path.join(ROOT, "docs", "superpowers", "progress.md")
    if not os.path.exists(p):
        return
    now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).strftime("%Y-%m-%dT%H:%M:%S+08:00")
    s = open(p, encoding="utf-8").read()
    s2 = re.sub(r"^- last_active: .*$", f"- last_active: {now}", s, flags=re.M)
    if s2 != s:
        open(p, "w", encoding="utf-8", newline="\n").write(s2)


def find_run(tok, wf, sha):
    runs = api(f"/actions/workflows/{wf}/runs?head_sha={sha}&per_page=10", tok).get("workflow_runs", [])
    return max(runs, key=lambda r: r["run_number"]) if runs else None


def main():
    kind = sys.argv[1] if len(sys.argv) > 1 else ""
    if kind not in WORKFLOW:
        sys.exit("用法：scripts/ci.sh core|ios")
    wf = WORKFLOW[kind]
    tok = token()
    subprocess.run(["git", "push", "-q", "origin", "HEAD:main"], cwd=ROOT, check=True)
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    print(f"[ci] {kind} @ {sha[:7]}", flush=True)
    deadline = time.time() + TIMEOUT_MIN[kind] * 60
    dispatched = False
    start = time.time()
    run = None
    while time.time() < deadline:
        heartbeat()
        run = find_run(tok, wf, sha)
        if run is None and kind == "ios" and not dispatched and time.time() - start > 45:
            api(f"/actions/workflows/{wf}/dispatches", tok, "POST", {"ref": "main"})
            dispatched = True
            print("[ci] push 沒觸發 ios.yml，已用 workflow_dispatch 觸發", flush=True)
        if run and run["status"] == "completed":
            break
        time.sleep(20)
    else:
        sys.exit(f"[ci] 逾時 {TIMEOUT_MIN[kind]} 分鐘，run={run and run['html_url']}")
    heartbeat()
    print(f"[ci] run #{run['run_number']} {run['conclusion']}  {run['html_url']}")
    jobs = api(f"/actions/runs/{run['id']}/jobs", tok).get("jobs", [])
    os.makedirs(os.path.join(ROOT, ".ci"), exist_ok=True)
    full = []
    for job in jobs:
        for st in job.get("steps", []):
            mark = "OK " if st["conclusion"] == "success" else ("-- " if st["conclusion"] == "skipped" else "XX ")
            print(f"  {mark}{job['name']} / {st['name']}")
        log = api(f"/actions/jobs/{job['id']}/logs", tok, raw=True)
        full.append(log)
    text = "\n".join(full)
    open(os.path.join(ROOT, ".ci", f"last-{kind}.log"), "w", encoding="utf-8").write(text)
    lines = [re.sub(r"^\S+Z ", "", l) for l in text.splitlines()]
    summary = [l for l in lines if re.search(r"Executed \d+ tests?|Test Suite .* (passed|failed)|warnings? count|passedTests|failedTests|skippedTests|Xcode \d|Swift version", l)]
    for l in summary[-12:]:
        print("  " + l)
    if run["conclusion"] != "success":
        errs = [l for l in lines if re.search(r"error:|failed|XCTAssert|FAIL", l)]
        print("---- 錯誤相關行（最後 60 行）----")
        for l in errs[-60:]:
            print(l[:300])
        sys.exit(1)


if __name__ == "__main__":
    main()
