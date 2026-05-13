You are publishing a new TangoDisplay release to GitHub. The user may have provided the new version number as an argument: "$ARGUMENTS"

Work through all 9 steps below in order. Complete each step fully before moving to the next. Do not skip steps.

---

## Step 1 — Determine the new version

Read `Install.sh` and find:
- `CFBundleShortVersionString` — current semantic version (e.g. `3.10.0`)
- `CFBundleVersion` — current build integer (e.g. `39`)

If `$ARGUMENTS` is non-empty, use it as the new semantic version.
If `$ARGUMENTS` is empty, ask the user: "What should the new version be? (current: X.Y.Z)"

The new `CFBundleVersion` is always the current integer + 1.

---

## Step 2 — Bump version in `Install.sh`

Edit `Install.sh` to update:
- `CFBundleVersion` → new integer
- `CFBundleShortVersionString` → new semantic version

---

## Step 3 — Update `README.md`

1. Find the line in the Installation section that references the previous zip filename and update it:
   `TangoDisplay-vOLD-universal.zip` → `TangoDisplay-vNEW-universal.zip`

2. Prepend a new changelog entry immediately after the `## Changelog` heading:

   ```
   ### vX.Y.Z
   - <release notes>
   ```

   If the user has not provided release notes, draft them by running `git log` to see commits since the last tag, then summarise the changes accurately. Show the draft to the user and ask them to confirm before writing it.

---

## Step 4 — Update docs in `docs/`

Check which files in `docs/` are relevant to the changes in this release (use `git diff` to identify touched areas). Update any affected doc files to reflect new or changed behaviour. The primary doc for built-in player changes is `docs/Built-In-Player.md`.

If no docs need updating, skip this step.

---

## Step 5 — Commit and push to `main`

Stage only the files relevant to this release. Do NOT stage unrelated pre-existing modified files — check `git status` and be selective. Typical files to stage:
- `Install.sh`
- `README.md`
- Any updated `docs/*.md` files
- Any source files changed in this release

Commit with message: `Bump version to X.Y.Z; <one-line summary of changes>`

Push to `main`.

---

## Step 6 — Build

Run:
```bash
bash Install.sh
```

After the build completes, verify the installed version:
```bash
defaults read /Applications/TangoDisplay.app/Contents/Info.plist CFBundleShortVersionString
```

Confirm it matches the new version before continuing.

---

## Step 7 — Create the release zip

```bash
ditto -c -k --sequesterRsrc --keepParent TangoDisplay.app TangoDisplay-vX.Y.Z-universal.zip
```

Replace `X.Y.Z` with the actual new version.

---

## Step 8 — Create the GitHub release and upload the zip

Retrieve the token from the macOS keychain:
```bash
TOKEN=$(security find-internet-password -s github.com -w)
```

**Important:** Always use Python for the GitHub API calls — do not use curl with inline JSON strings (shell escaping causes `Invalid control character` errors).

First check whether a release for this tag already exists (this can happen if a previous attempt partially succeeded):
```bash
TOKEN=$(security find-internet-password -s github.com -w)
curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/richardsladetdj-creator/TangoDisplay/releases/tags/vX.Y.Z" | \
  python3 -c "import sys,json; r=json.load(sys.stdin); print('exists:', r.get('id', 'no'))"
```

**If the release does NOT exist**, create it using Python:
```bash
TOKEN=$(security find-internet-password -s github.com -w) python3 << 'PYEOF'
import json, urllib.request, ssl, os

token = os.environ['TOKEN']
body = {
    "tag_name": "vX.Y.Z",
    "name": "vX.Y.Z",
    "body": "<release notes — same text as README changelog entry>",
    "draft": False,
    "prerelease": False
}
req = urllib.request.Request(
    "https://api.github.com/repos/richardsladetdj-creator/TangoDisplay/releases",
    data=json.dumps(body).encode(),
    headers={
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json"
    }
)
with urllib.request.urlopen(req, context=ssl.create_default_context()) as r:
    resp = json.load(r)
    print("ID:", resp["id"])
    print("URL:", resp["html_url"])
    print("UPLOAD:", resp["upload_url"].split("{")[0])
PYEOF
```

**If the release already exists**, fetch its upload URL:
```bash
TOKEN=$(security find-internet-password -s github.com -w)
curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/richardsladetdj-creator/TangoDisplay/releases/tags/vX.Y.Z" | \
  python3 -c "import sys,json; r=json.load(sys.stdin); print(r['upload_url'].split('{')[0])"
```

**Upload the zip asset** using the upload URL from above:
```bash
TOKEN=$(security find-internet-password -s github.com -w)
curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/zip" \
  --data-binary @TangoDisplay-vX.Y.Z-universal.zip \
  "<UPLOAD_URL>?name=TangoDisplay-vX.Y.Z-universal.zip" | \
  python3 -c "import sys,json; r=json.load(sys.stdin); print('Asset:', r.get('browser_download_url','ERROR'))"
```

Report the asset download URL to the user.

---

## Step 9 — Push updated docs to the wiki

Check whether the wiki is already cloned locally:
```bash
ls /Users/richardslade/SourceCode/TangoDisplay.wiki 2>/dev/null || echo "not cloned"
```

If not cloned:
```bash
git clone https://github.com/richardsladetdj-creator/TangoDisplay.wiki.git /Users/richardslade/SourceCode/TangoDisplay.wiki
```

Copy every `docs/*.md` file that was updated in this release to the wiki directory. Example:
```bash
cp docs/Built-In-Player.md /Users/richardslade/SourceCode/TangoDisplay.wiki/
```

Then commit and push the wiki:
```bash
cd /Users/richardslade/SourceCode/TangoDisplay.wiki && \
git add -A && \
git commit -m "vX.Y.Z: <brief summary>" && \
git push
```

If no docs were updated in this release, skip this step.

---

## Done

Report a summary:
- Version bumped from OLD → NEW
- GitHub release URL
- Asset download URL
- Whether the wiki was updated
