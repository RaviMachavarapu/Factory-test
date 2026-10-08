# macOS distribution checklist (tauri stack)

REQ-352: this checklist is copied into the instance at
`docs/releases/store-checklist.md`; `/release` appends it to each release's
notes and `release.yml` refuses an app release without it.

1. **Apple Developer Program** — US$99/year. Enrollment takes anywhere from
   a day to a few weeks for organizations (D-U-N-S number verification).
2. **Bundle identifier** — replace `com.example.<pkg>` in
   `src-tauri/tauri.conf.json` `identifier` with your own reverse-DNS id.
3. **Signing secrets** (fixed names, read by `release.yml`'s `sign` job,
   REQ-386) — add them as environment secrets of the `release` environment
   (Settings → Environments → `release`), never as repository secrets:
   - `APPLE_CERTIFICATE_P12` — base64-encoded `.p12` export of a Developer
     ID Application certificate.
   - `APPLE_CERTIFICATE_PASSWORD` — the `.p12` export password.
   - `APPLE_ID` — the Apple ID used for notarization.
   - `APPLE_TEAM_ID` — your Apple Developer Team ID.
   - `APPLE_APP_PASSWORD` — an app-specific password for that Apple ID.
4. **Notarization** — `xcrun notarytool submit --wait`, then
   `xcrun stapler staple` on the built `.app`/`.dmg`.
5. **Gatekeeper** — verify with `spctl --assess --type execute -vv`; an
   unsigned app opens via System Settings → Privacy & Security → Open
   Anyway.
6. **Packaging** — ship the `.dmg` produced by `release-tauri.sh`.
7. **Mac App Store vs. direct Developer ID distribution** — the App Store
   needs sandbox entitlements, an App Store Connect record and an Apple
   Distribution certificate; not automated in v3.2. Direct Developer ID
   distribution (signed + notarized `.dmg`) is what this pack builds.
8. **Architecture** — arm64 only. Intel Macs need a
   `--target universal-apple-darwin` build, not produced by this pack.
9. **Entitlements** — the signed `.app` carries the entitlements the project
   committed: the file `src-tauri/tauri.conf.json` names in
   `bundle.macOS.entitlements` — add `com.apple.security.app-sandbox` there to
   sandbox the app. Without one, the pack's
   `.github/actions/release/entitlements.plist` (empty: no sandbox) is the
   fallback. The set the unsigned app embeds is only compared: a key it
   carries that the committed set lacks, or carries with another value, stops the signing (exit 1, naming the
   key), so add it to the committed file by a reviewed PR. `com.apple.security.get-task-allow` is never signed in.

Re-run all jobs of the tag's `release.yml` run (GitHub refuses a re-run once the run is 30 days old), or dispatch `release.yml` on the tag: `gh workflow run release.yml --ref v<version>`.

Re-run the tag after adding the secrets and observe `signed: true`.
