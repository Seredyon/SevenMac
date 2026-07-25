# SevenMac - a real 7-Zip GUI for macOS (Apple Silicon)

SevenMac is a native SwiftUI file-manager style front end for the official
**7-Zip console engine (`7zz`)**, built for macOS 13+ on Apple Silicon (M1/M2/M3/M4).
It is modelled on the Windows 7-Zip File Manager / NanaZip workflow - browse, open
archives like folders, add, extract, test, checksum, benchmark - instead of the
"drop a file and hope" model most Mac archivers use.

## Why this exists

7-Zip ships **console-only** binaries for macOS. The existing Mac options are
either drop-target utilities (Keka, The Unarchiver) or unmaintained Python/Qt
wrappers. SevenMac is a native, keyboard-driven, two-column *file manager* with
full 7-Zip switch coverage.

| Project | Platform | Style | Native |
|---|---|---|---|
| 7-Zip File Manager | Windows | file manager | yes |
| NanaZip | Windows 10/11 | file manager (WinUI) | yes |
| Keka | macOS | drop target + prefs | yes (no archive browser/editor) |
| 7zip-pyside | macOS | file manager | no (Python/Qt) |
| Archivist | macOS | alpha, Python | no |
| **SevenMac** | **macOS arm64** | **file manager** | **yes (SwiftUI)** |

## Features

- **Browse the filesystem and archives in one window.** Double-click an archive
  to step inside it like a folder; nested folders inside the archive are virtualised
  from `7zz l -slt` output.
- **Columns:** name, size, packed size, ratio, modified date, kind. Sortable, filterable.
- **Add to archive** sheet: format (7z/ZIP/TAR/GZIP/BZIP2/XZ/WIM), level Store→Ultra,
  solid mode, thread count, AES-256 password, **encrypt file names** (`-mhe=on`),
  split volumes (`-v100m`), delete source after compression (`-sdel`).
- **Extract** sheet: destination picker, keep/flatten paths (`x` vs `e`),
  overwrite policy (`-aoa/-aos/-aou/-aot`), extract only the selection.
- **Test integrity** (`t`), **remove from archive** (`d`), **checksums** (`h -scrcSHA256`),
  **benchmark** (`b -md=…`) with live output.
- **Live progress** parsed from `-bsp1`, with Cancel (terminates the child process).
- **Encrypted archives**: password prompt on open, header-encrypted archives supported.
  `stdin` is closed so `7zz` can never hang on an invisible prompt.
- Drag & drop onto the window (archive → open, files → compress), Finder reveal,
  full menu bar with shortcuts, Settings for default format/level and engine path.

## Layout

```
SevenMac/
├── Package.swift                  # SwiftPM, macOS 13, executable target
├── Sources/SevenMac/
│   ├── SevenMacApp.swift          # App entry, menu commands
│   ├── Core/
│   │   ├── SevenZBinary.swift     # locate bundled / brew / custom 7zz
│   │   ├── SevenZRunner.swift     # Process wrapper, progress + error mapping
│   │   ├── ArchiveEntry.swift     # `l -slt` parser + archive summary
│   │   ├── ArchiveService.swift   # command-line builders, formats, options
│   │   ├── JobRunner.swift        # one job at a time, publishes progress
│   │   └── AppSettings.swift      # UserDefaults-backed settings, formatters
│   ├── Model/BrowserModel.swift   # navigation, folder + virtual archive tree
│   └── Views/                     # ContentView, Add, Extract, Progress,
│                                  # Password, Info, Benchmark, Settings
├── Resources/
│   ├── Info.plist                 # bundle metadata + archive document types
│   ├── bin/7zz                    # official 7-Zip 26.02 console binary (universal)
│   └── AppIcon.iconset/           # 10 PNGs, ready for iconutil
└── scripts/
    ├── build_app.sh               # swift build + .app assembly + ad-hoc signing
    ├── make_icon.sh               # iconset → AppIcon.icns
    └── dev_run.sh                 # swift run for quick iteration
```

## Installation

1. Download **SevenMac.dmg** from the latest
   [release](../../releases/latest).
2. Open the DMG and drag **SevenMac** into **Applications**.
3. First launch only: right-click the app → **Open** (the build is not
   notarized by Apple, so macOS shows a one-time warning).