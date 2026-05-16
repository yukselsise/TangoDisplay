# TangoDisplay — Dev Notes

## Release Process

Use the `/release` slash command — it handles the full workflow automatically:

```
/release X.Y.Z
```

Steps covered: version bump in `Install.sh`, README changelog + download link, docs update, commit/push, `bash Install.sh` build, zip, GitHub release creation, asset upload, and wiki sync.

- ALWAYS follow the procedure in `.claude/commands/release.md` — do not start exploring or making changes first
- Use Python for GitHub API calls — never inline JSON in a curl `-d` string. Shell escaping produces `Invalid control character` errors on release body text
- When creating GitHub releases via `gh release create`, use `--notes-file` instead of inline `--notes` to avoid JSON escaping issues with special characters (em dashes, ⌘ symbols, control chars)
- If a tag already exists from a prior attempt, update the existing release instead of creating a new one

GitHub token is stored in the macOS keychain:
```bash
TOKEN=$(security find-internet-password -s github.com -w)
```

## Build Verification

- After any code change, run the build and confirm success before reporting completion
- For Swift code: `await` cannot be used inside `??` autoclosures — unwrap with `if let` instead
- When changing UI layout, verify against any reference screenshot provided — do not assume first-pass interpretation is correct
