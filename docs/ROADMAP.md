# Where SevenMac goes next

Version 1.3 makes editing archive contents practical. The next releases should make SevenMac especially useful for people inspecting app packages, mods and release artifacts.

## 1. Compare two archives

Show added, removed and changed entries, then a text diff for configs and manifests. Compare by content hash when CRCs are absent; avoid unpacking unchanged data. This would help with APK releases, mod packs, EPUBs and deployment bundles.

A useful first version: open two ZIP/7z files, compare paths and hashes, export a small report. Do not call a metadata-only comparison a content comparison.

## 2. Package inspector

An APK overview could show package name, version, permissions, native architectures and certificate fingerprints. A separate, optional Android SDK integration could provide `zipalign` and `apksigner`. Keep signing keys in user-controlled storage and never silently reuse a developer key. Binary Android XML needs a real parser; displaying its raw bytes is not a manifest viewer.

## 3. Preview and nested archives

Add image/PDF previews and a stack for opening ZIP-inside-ZIP, JARs inside packages and compressed TARs. Enforce temporary-storage and recursion limits. Make it clear which parent archives will change before saving a nested edit.

## 4. Extraction queue and preflight

Let users queue several archives, choose collision rules once, and see progress per job. Before extraction, show required disk space, suspicious paths, symbolic links and extreme expansion ratios. Keep this local; no file upload is necessary.

## 5. Distribution that gets out of the way

Apple notarization, a signed update feed, Finder Quick Look and a Homebrew cask would reduce installation friction. Developer ID and notarization require the owner's Apple developer identity. Build a release regression corpus first, including real-world split and encrypted samples.

## Positioning

“More extensions” alone is a weak differentiator. BetterZip already provides archive editing and Quick Look; Keka has an established compression workflow. A free, native tool focused on package inspection, archive comparison and reliable edits has a clearer audience: Mac developers, mod authors and technical users. This is a product hypothesis, not evidence of future popularity.

Sources checked September 23, 2026:

- [BetterZip](https://macitbetter.com/)
- [BetterZip Quick Look](https://macitbetter.com/library/betterzip/docs/quick-look-extension/)
- [Keka changelog](https://www.keka.io/changelog/)
- [Android apksigner](https://developer.android.com/tools/apksigner)
