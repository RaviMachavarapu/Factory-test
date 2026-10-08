# macOS distribution checklist (flutter stack)

REQ-352: this checklist is copied into the instance at
`docs/releases/store-checklist.md`; `/release` appends it to each release's
notes and `release.yml` refuses an app release without it.

1. **Apple Developer Program** — US$99/year. Enrollment takes anywhere from
   a day to a few weeks for organizations (D-U-N-S number verification).
2. **Bundle identifier** — replace `com.example.<pkg>` in
   `macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_BUNDLE_IDENTIFIER`)
   with your own reverse-DNS id.
3. **Signing secrets** (fixed names, read by `release.yml`'s `sign` job,
   REQ-386) — add them as environment secrets of the `release` environment
   (Settings → Environments → `release`), never as repository secrets:
   - `APPLE_CERTIFICATE_P12` — base64-encoded `.p12` export of a Developer
     ID Application certificate.
   - `APPLE_CERTIFICATE_PASSWORD` — the `.p12` export password.
   - `APPLE_ID` — the Apple ID used for notarization.
   - `APPLE_TEAM_ID` — your Apple Developer Team ID.
   - `APPLE_APP_PASSWORD` — an app-specific password for that Apple ID.
4. **Notarization** — `xcrun notarytool submit --wait` on a zip of the
   signed `.app`, then `xcrun stapler staple` on the `.app` itself and a
   fresh zip of the stapled app (a zip cannot be stapled;
   `release-sign.sh` does exactly this).
5. **Gatekeeper** — verify with `spctl --assess --type execute -vv`; an
   unsigned app opens via System Settings → Privacy & Security → Open
   Anyway.
6. **Packaging** — `release-flutter.sh` zips the built `.app` with
   `ditto -c -k --sequesterRsrc --keepParent` (preserves code-signing
   metadata and extended attributes, unlike `zip(1)`); a `.dmg` via
   `hdiutil create` is optional and not produced by this pack.
7. **Mac App Store vs. direct Developer ID distribution** — the App Store
   needs sandbox entitlements, an App Store Connect record and an Apple
   Distribution certificate; not automated in v3.2. Direct Developer ID
   distribution (signed + notarized `.zip`) is what this pack builds.
8. **Architecture** — arm64 only, the pack's choice (`macos_archs`). The
   earlier Flutter 3.35.5's universal macOS build failed on Xcode 27
   (`lipo -verify_arch` accepts one architecture per invocation; measured
   2026-09-25); Flutter 3.47.6's builds (measured 2026-10-04), so an
   instance that needs Intel Macs can delete `ARCHS = arm64` from
   `Release.xcconfig`. Intel Macs are not supported by this pack's release
   build as shipped.
9. **Minimum macOS version** — 12.0 (`macos/Podfile`'s platform and every
   `MACOSX_DEPLOYMENT_TARGET` in `macos/Runner.xcodeproj/project.pbxproj`;
   `Release.xcconfig` carries only `ARCHS = arm64`);
   the generator's default of 10.15 is rejected by Xcode 27.
10. **Entitlements** — the signed `.app` carries the entitlements of
    `macos/Runner/Release.entitlements`, the file the release build is made
    with (the generator's app sandbox included, so the signed release is as
    sandboxed as the unsigned one and keeps its data under
    `~/Library/Containers/<bundle id>/`); the pack's
    `.github/actions/release/entitlements.plist` is the fallback when that file
    is absent. The set the unsigned app embeds is only compared: a key it
    carries that the committed set lacks, or carries with another value, stops the signing (exit 1, naming the
    key), so add it to the committed file by a reviewed PR.
    `com.apple.security.get-task-allow` is never signed in.

Re-run all jobs of the tag's `release.yml` run (GitHub refuses a re-run once the run is 30 days old), or dispatch `release.yml` on the tag: `gh workflow run release.yml --ref v<version>`.

Re-run the tag after adding the secrets and observe `signed: true`.
