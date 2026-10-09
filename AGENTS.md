# AGENTS.md

<!-- moli-rules:start -->
## Moli rules (copied verbatim from MoliSpec; do not edit)

These rules apply to every Moli repository. The full standards live in the private repo `MoliDuo/MoliSpec` (`standards/`).

**Naming**
- Product name `MoliFoo` (repo, package, file and identifier names, no spaces). User-facing name is `Moli Foo` (one space): window titles, app name, UI text, README title, Release titles.

**Deploy and CI**
- Deploy only after CI passes. Merging to `main` deploys to production (server apps), so run the check entry (`npm run check` or the stack's equivalent) locally before opening the PR, and watch CI and the deploy after it merges.
- Keep the CI names fixed: workflows `ci` / `deploy` / `release` / `codeql`; jobs `check`, `gitleaks`, `build`, `integration`, `ci-gate`.
- Never delete or skip tests, or loosen lint rules, to make a check pass.

**Git**
- Conventional Commits (`feat(scope): subject`).
- Never push to `main` directly. Every change, however small, goes on a new branch and is merged through a PR with auto-merge on. Before starting, update local `main` (`git switch main && git pull`) and branch from it; if a push is rejected or the branch is behind, pull the latest `main` and merge or rebase it in.
- Never force-push `main`. Roll back with `git revert`.

**Secrets and private information**
- Never commit secrets, `.env` files, keys, or internal information (server addresses, hostnames, Tailscale addresses, personal emails). Use obviously fake values in tests and examples (`test-token`, `example.com`, `192.0.2.1`).
- Never print secret values in logs, chat, or commits. Never store secrets in the OS keychain. Runtime secrets live in the server `.env` (mode 600); build and release secrets live in GitHub organization secrets.
- Do not copy a shared (organization-level) secret into repository-level secrets unless the administrator has said so.

**Login, data, config**
- Sign-in is Authelia only. Do not build your own accounts, passwords or registration pages.
- Database and settings schemas only add; never delete or rename an existing field in one step. Migrations must keep the previous app version working.
- Clients are offline-first and the server is authoritative. Settings are read in the order defined in the config standard; do not invent a second source.
- Server apps expose `GET /healthz` returning `{"ok": true, "version": "<commit sha>"}`, run as non-root, take config from environment variables, and publish no host ports.

**Working with the user**
- Do only what was asked. Do not publish, delete, or change shared settings (GitHub org, server, DNS) without being asked.
- Reply to the user in Chinese, briefly.
<!-- moli-rules:end -->

## About this project

Moli Switch is a macOS menu bar utility that switches the keyboard input method by the frontmost app,
by the program running in Terminal or iTerm2, and by the focused text field. It can also switch to
English while typing a `/` command or while Shift is held. It was called AutoInputSwitcher before.
Design: `docs/architecture.md`. User-facing behaviour: `README.md`.

## Run and test

- macOS 14+ with a Swift 6 toolchain (Command Line Tools or Xcode). There is no Linux build.
- Check (same as CI): `Scripts/check.sh` — SwiftFormat lint, SwiftLint, build with warnings as errors,
  `swift run MoliSwitchCoreChecks`, unit tests. `Scripts/check.sh --fix` applies the formatter and the
  autocorrectable lint fixes.
- Package locally: `Scripts/package-release.sh`, then `Scripts/verify-package.sh`. Local builds are
  ad-hoc signed, so macOS asks for the Accessibility grant again after each rebuild.
  `UNIVERSAL=0 Scripts/build-app.sh` builds only the native architecture, which is faster.
- Run: open `.build/MoliSwitch.app`. Quit any installed copy first, or both switch input methods.
- Logs: `log stream --predicate 'subsystem == "com.moli.MoliSwitch"' --level debug`. The usage log
  (JSON Lines, one file per day) is in `~/Library/Application Support/MoliSwitch/usage/`.
- Release: bump `VERSION`, commit `chore(release): vX.Y.Z` through a PR, then tag `vX.Y.Z` on `main`
  and push the tag. `.github/workflows/release.yml` builds, signs, publishes and checks the live feed.
  `CFBundleVersion` is derived from `VERSION` in `Scripts/common.sh`.

## Layout

- `Sources/MoliSwitchCore`: pure logic with no AppKit — rules and their stores, rule resolution,
  the slash-command and Shift trackers, the usage log and its analyser. Unit tested.
- `Sources/MoliSwitchApp`: AppKit and SwiftUI — runtime, input source switching, Accessibility
  probing of the focused field, terminal program detection, key event monitor, Sparkle updater,
  migration from AutoInputSwitcher, main window (`Views/`).
- `Sources/MoliSwitch/main.swift`: entry point only.
- `Sources/MoliSwitchCoreChecks`: a self-check executable run by `Scripts/check.sh`.
- `Scripts/`: check, build, package, DMG, appcast and release notes. Names and the version are in
  `Scripts/common.sh`.
- `Config/`: the app icon (from the MoliSpec design system), the Sparkle public key and the signing
  certificate fingerprint.

## Conventions

- Times shown to the user and the day boundaries of the usage log are in Singapore time (`MoliTime`).
- Log everything that helps debugging; this app has one user, so be generous rather than adding
  log lines one at a time.
- Rule and settings files only gain fields; never rename or remove one (MoliSpec 009). A file that
  fails to load is left untouched and editing is paused until it loads.
- Private or fragile macOS behaviour (Accessibility attributes, input source quirks) is probed and
  logged rather than assumed; keep the fallbacks.

## Do not touch

- `Config/SparklePublicKey.txt` and `Config/CodeSigningCertificate.txt`: changing either cuts installed
  apps off from updates or resets every user's Accessibility grant.
- The bundle identifier `com.moli.MoliSwitch` (an exception in `moli.yaml`).
- The feed URL `releases/latest/download/appcast.xml`: installed copies read updates from it.
