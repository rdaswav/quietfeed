# Quiet Feed build conventions

- Never edit `.xcodeproj` by hand. Change `project.yml` and run `xcodegen generate`.
- Never use literal colours in views. Use tokens from `App/Theme.swift`.
- Run `./scripts/verify.sh` before committing.
- One task per commit, message `T01: summary` (task id first).
- Never weaken, delete or skip a test, and never edit `scripts/verify.sh` to make something pass.
- `rules/rulepack.json` and `web/runtime.js` are single sources; never keep a second edited copy.
