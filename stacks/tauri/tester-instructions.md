# Opening <app> <version>, an unsigned build

<app> <version> is not signed or notarized by Apple (the release was built with
`signing: none`), so macOS blocks it on first launch. It is safe to open if you
trust the person who sent it and the download is the file the release lists.

**Check the download**

The release's attached `manifest.json` lists every file with its SHA-256 (the
release notes' Artifacts table lists only the source archive). In Terminal,
run `shasum -a 256` on the file you downloaded, for example
`shasum -a 256 ~/Downloads/<name of the file>`, and compare the result with the
`sha256` that `manifest.json` gives for that file name. If they differ, do not
open it.

**Install it**

Double-click the .dmg to open it, drag `<app>.app` into the Applications
folder, then eject the disk image (Finder's eject button next to it).

Then open it once the way your macOS version asks:

**macOS 15 (Sequoia) and later**

1. Open `<app>.app` in Applications (double-click it). macOS says it cannot
   verify the app; choose Done.
2. Open System Settings, then Privacy & Security, and scroll to the Security
   section.
3. Click **Open Anyway** next to "<app>" was blocked, confirm with your
   password, then Open.

**macOS 14 (Sonoma) and earlier**

1. Control-click (or right-click) `<app>.app` in Applications and choose Open.
2. Choose Open again in the dialog.

**From the terminal (any version)**

Remove the quarantine flag the download added, then launch normally:

```
xattr -dr com.apple.quarantine /Applications/<app>.app
```

You only need to do this once per download.
