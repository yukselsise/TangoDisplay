# TangoDisplay — Dev Notes

## Release workflow

Use the `/release` slash command — it handles the full workflow automatically:

```
/release X.Y.Z
```

Steps covered: version bump in `Install.sh`, README changelog + download link, docs update, commit/push, `bash Install.sh` build, zip, GitHub release creation, asset upload, and wiki sync.

**Key implementation note:** Always use Python for GitHub API calls — never inline JSON in a curl `-d` string. Shell escaping produces `Invalid control character` errors on release body text. See `.claude/commands/release.md` for the full step-by-step.

GitHub token is stored in the macOS keychain:
```bash
TOKEN=$(security find-internet-password -s github.com -w)
```
