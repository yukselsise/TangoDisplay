Sync updated docs to the TangoDisplay GitHub wiki. Run this after editing any files in `docs/` outside of a full release.

## Step 1 — Identify changed docs

Check which `docs/*.md` files have changed:
```bash
git diff --name-only HEAD -- 'docs/*.md'
```

If no docs have changed, report that and stop — nothing to sync.

## Step 2 — Commit and push the main repo's doc changes

```bash
git add docs/*.md && \
git commit -m "<brief summary of doc changes>" && \
git push
```

## Step 3 — Ensure the wiki is cloned

```bash
ls /Users/richardslade/SourceCode/TangoDisplay.wiki 2>/dev/null || echo "not cloned"
```

If not cloned:
```bash
git clone https://github.com/richardsladetdj-creator/TangoDisplay.wiki.git /Users/richardslade/SourceCode/TangoDisplay.wiki
```

## Step 4 — Copy updated docs

Copy each changed `docs/*.md` file into the wiki directory. Example:
```bash
cp docs/Built-In-Player.md /Users/richardslade/SourceCode/TangoDisplay.wiki/
```

## Step 5 — Commit and push the wiki

```bash
cd /Users/richardslade/SourceCode/TangoDisplay.wiki && \
git add -A && \
git commit -m "<brief summary of doc changes>" && \
git push
```

## Step 6 — Report

Confirm which files were synced and the wiki commit hash.
