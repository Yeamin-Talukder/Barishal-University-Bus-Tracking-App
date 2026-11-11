"""Build the BU Bus Tracker website into website/public/.

Copies website/src/ and fills in the values from website/site.config.json:

  siteUrl         where the site will live, ending in "/". Used for the
                  canonical link, link previews, the sitemap and robots.txt.
  githubOwner     GitHub user or organisation, e.g. "your-name". Leave empty
                  until the repository exists: the site then shows
                  "coming soon" instead of download numbers.
  githubRepo      repository name, e.g. "bu-bus-tracker".
  apkNamePattern  optional regular expression to choose which APK in a
                  release is offered, e.g. "arm64". By default a "universal"
                  APK is preferred, then "arm64", then the first APK.

The build also asks GitHub for the latest releases and saves the answer as
public/release.json. A visitor's browser asks GitHub too, but GitHub answers
only 60 questions an hour from one network, so on a busy campus network the
saved copy is what keeps the download button working. If GitHub cannot be
reached while building, no copy is saved and the site works as before. Set
GITHUB_TOKEN in the environment to ask with a token (the deploy workflow
does).

Usage, from the project root:

    python website/build.py

Preview with:  python -m http.server 5700 --directory website/public
"""
import datetime
import json
import os
import shutil
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
OUT = os.path.join(HERE, "public")
TEXT = {".html", ".xml", ".txt", ".css", ".js", ".webmanifest", ".json"}


def save_release_copy(owner, repo, now):
    """Writes public/release.json from GitHub's own answer. Returns how many
    releases were saved, or None when GitHub could not be asked."""
    api = f"https://api.github.com/repos/{owner}/{repo}"
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "site-build"}
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if token:
        headers["Authorization"] = "Bearer " + token

    def ask(url):
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=15) as res:
            return json.load(res)

    try:
        info = ask(api)
        releases = ask(api + "/releases?per_page=30")
    except Exception as e:  # no network, rate limit, repository not found
        print(f"note: release details were not saved ({e}); the site will ask GitHub only.")
        return None

    # Only what the page reads, so nothing else is published by accident.
    data = {
        "t": int(now.timestamp() * 1000),
        "repo": {
            "stargazers_count": info.get("stargazers_count", 0),
            "forks_count": info.get("forks_count", 0),
        },
        "releases": [
            {
                "tag_name": r.get("tag_name"),
                "name": r.get("name"),
                "prerelease": bool(r.get("prerelease")),
                "draft": False,
                "published_at": r.get("published_at"),
                "body": r.get("body") or "",
                "html_url": r.get("html_url"),
                "assets": [
                    {
                        "name": a.get("name"),
                        "size": a.get("size", 0),
                        "digest": a.get("digest"),
                        "download_count": a.get("download_count", 0),
                        "browser_download_url": a.get("browser_download_url"),
                    }
                    for a in r.get("assets", [])
                ],
            }
            for r in releases
            if not r.get("draft")
        ],
    }
    with open(os.path.join(OUT, "release.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1)
    return len(data["releases"])


def main():
    with open(os.path.join(HERE, "site.config.json"), encoding="utf-8") as f:
        cfg = json.load(f)
    site_url = cfg.get("siteUrl", "").strip()
    if not site_url.endswith("/"):
        site_url += "/"
    now = datetime.datetime.now(datetime.timezone.utc)
    values = {
        "{{SITE_URL}}": site_url,
        "{{BUILD_DATE}}": now.strftime("%Y-%m-%d"),
        "{{BUILD_ID}}": now.strftime("%Y%m%d%H%M"),
    }

    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    shutil.copytree(SRC, OUT)

    count = 0
    for folder, _, files in os.walk(OUT):
        for name in files:
            if os.path.splitext(name)[1] not in TEXT:
                continue
            path = os.path.join(folder, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            new = text
            for key, value in values.items():
                new = new.replace(key, value)
            if new != text:
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write(new)
                count += 1

    runtime = {
        "githubOwner": cfg.get("githubOwner", "").strip(),
        "githubRepo": cfg.get("githubRepo", "").strip(),
        "apkNamePattern": cfg.get("apkNamePattern", "").strip(),
    }
    with open(os.path.join(OUT, "js", "config.js"), "w", encoding="utf-8", newline="\n") as f:
        f.write("// Generated by website/build.py from site.config.json. Do not edit.\n")
        f.write("window.BUBT_CONFIG = " + json.dumps(runtime, indent=2) + ";\n")

    # Fail loudly if a placeholder was missed.
    for folder, _, files in os.walk(OUT):
        for name in files:
            if os.path.splitext(name)[1] in TEXT:
                with open(os.path.join(folder, name), encoding="utf-8") as f:
                    if "{{" in f.read() and name.endswith((".html", ".xml", ".txt")):
                        print(f"error: unfilled placeholder in {name}", file=sys.stderr)
                        return 1

    if runtime["githubOwner"] and runtime["githubRepo"]:
        saved = save_release_copy(runtime["githubOwner"], runtime["githubRepo"], now)
        if saved is not None:
            print(f"Saved a copy of {saved} release(s) from GitHub as release.json.")

    print(f"Built {os.path.relpath(OUT)} ({count} files filled in) for {site_url}")
    if "localhost" in site_url or "127.0.0.1" in site_url:
        print("note: siteUrl is a local address. Set the real address in site.config.json before publishing.")
    if not (runtime["githubOwner"] and runtime["githubRepo"]):
        print("note: no GitHub repository set; the download area shows 'coming soon'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
