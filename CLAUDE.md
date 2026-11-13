# Quiet Feed build conventions

- Never edit `.xcodeproj` by hand. Change `project.yml` and run `xcodegen generate`.
- Never use literal colours in views. Use tokens from `App/Theme.swift`.
- Run `./scripts/verify.sh` before committing.
- One task per commit, message `T01: summary` (task id first).
- Never weaken, delete or skip a test, and never edit `scripts/verify.sh` to make something pass.
- `rules/rulepack.json` and `web/runtime.js` are single sources; never keep a second edited copy.

- This repository is public. Never commit a LAN or private IP address, hostname, Apple Team ID, token, or personal path. Use placeholders such as `your-server`, and keep real values in the git-ignored `Local.xcconfig` or in app settings. Before every commit run `git grep -nE "192\.168|10\.[0-9]+\.[0-9]+\.[0-9]+"` and expect no output.
