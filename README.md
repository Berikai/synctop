# SyncTop 🔄
*Frictionless, mount-free selective folder synchronization to Google Drive on macOS.*

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Engine](https://img.shields.io/badge/Engine-rclone%20API-blueviolet)](https://rclone.org)

**SyncTop** is a minimalist, native macOS Menu Bar application that lets you selectively sync and backup local folders to Google Drive without the friction of terminal commands and **without mounting virtual cloud drives**.

---

## 💡 Why SyncTop?

| Traditional Method | The Pain Point |
| :--- | :--- |
| **Manual Terminal `rsync`** | Complex flags, tricky trailing slash semantics (`dir` vs `dir/`), no safety against accidental `--delete`, and standard `rsync` cannot talk directly to Google Drive's API. |
| **Google Drive App (Virtual Mount)** | Mounts virtual directories in `~/Library/CloudStorage` that trigger file-locking issues, stub-file timeouts, high memory usage, and break tools like compilers, `git`, or local databases. |
| **SyncTop** | **Zero mounts.** Direct cloud API synchronization. Native Menu Bar status item, 1-click sync, bidirectional edits with conflict copy protection, and preset ignore filters. |

---

## ✨ Features

- **☁️ Zero Virtual Mounts**: Talks directly to Google Drive's REST API over HTTPS using an underlying `rclone` engine. Your local folders remain regular, high-speed local folders.
- **🔄 Two-Way Sync (`bisync`) & Conflict Protection**: Synchronizes changes in both directions (local $\leftrightarrow$ Google Drive). If both sides edit the same file, SyncTop keeps the newer version and preserves the conflicting copy as `filename.sync-conflict.<ext>` so no work is ever lost.
- **⚡️ One-Way Backup & Restore**: Supports Push (Local $\to$ Cloud backup) and Pull (Cloud $\to$ Local restore) modes.
- **🖥 Menu Bar Extra & Detached Manager**:
  - Unobtrusive Menu Bar item with dynamic status icons (idle, animated spinning sync, error badge).
  - 1-Click "Sync All" and individual profile triggers.
  - Standalone Manager Window for configuring folder pairs, viewing live transfer speeds, and inspecting logs.
- **🗂 Interactive Google Drive Folder Browser**: Browse and create folders directly in your Google Drive visually inside the app—no manual cloud path typing needed. Includes graceful ancestor recovery if a directory doesn't exist yet.
- **🛡 1-Click Ignore Presets**:
  - **Developer Preset**: `node_modules/`, `.git/`, `.venv/`, `__pycache__/`, `target/`, `build/`, `dist/`, `DerivedData/`.
  - **macOS System Preset**: `.DS_Store`, `.Trash/`, `Thumbs.db`, `.Spotlight-V100/`.
  - **Custom Globs**: Easily add comma-separated custom exclusion rules.
  - Directly toggleable with 1-click pills on each folder pair card.
- **🔍 Safe Dry-Run Simulation**: Preview exactly which files will be copied, updated, or removed before a single byte moves, with color-coded action badges.
- **⏱ Flexible Background Scheduling**:
  - Set automatic sync intervals directly on folder cards via quick dropdown: **Every 5m, 15m, 30m, 1h, 4h, 12h, Daily, or Weekly**.
  - Live next-sync countdown indicators (e.g. *“Next: in 14m”*).
- **🚀 Start at Login**: Integrated macOS `SMAppService` toggle to run automatically in the menu bar at system boot.
- **☕️ Mac Sleep Prevention**: Uses native `IOPMAssertion` to keep your Mac awake during active file transfers and releases power assertions immediately upon completion.
- **🎯 Zero Dock Footprint**: Operates cleanly as an accessory utility (`LSUIElement`) from the Menu Bar without cluttering your macOS Dock.

---

## 🏗 Modular Architecture

SyncTop is built with a clean separation of concerns:

```text
SyncTop/
├── Package.swift                  # SPM manifest (macOS 14+)
├── scripts/
│   └── build_app.sh               # Builds standalone dist/SyncTop.app bundle
├── Sources/
│   ├── SyncTopCore/               # Headless, reusable core library
│   │   ├── Models/                # SyncProfile, SyncDirection, ExcludePreset, SyncProgress
│   │   ├── Engine/                # RcloneDiscovery, RcloneEngine, RcloneRemoteBrowser
│   │   ├── Services/              # ProfileStore (JSON), SyncScheduler
│   │   └── Utilities/             # ProcessRunner (AsyncStream), BookmarkManager
│   └── SyncTop/                   # Native macOS SwiftUI application
│       ├── SyncTopApp.swift       # MenuBarExtra & Window application entry
│       ├── State/                 # AppState (ObservableObject)
│       └── Views/                 # MenuBar, Manager Dashboard, Browser, DryRun
└── Tests/
    └── SyncTopTests/              # Standalone test runner & engine verification
```

---

## 🚀 Quickstart

### Prerequisites

SyncTop requires `rclone` installed on your Mac:
```bash
brew install rclone
```
And a configured Google Drive remote (default name `google:`):
```bash
rclone config
# Follow the interactive prompt to connect your Google Drive account
```

### Building & Running

1. **Clone the repository**:
   ```bash
   git clone https://github.com/berikai/SyncTop.git
   cd SyncTop
   ```

2. **Package the native macOS app**:
   ```bash
   ./scripts/build_app.sh
   ```

3. **Launch SyncTop**:
   ```bash
   open dist/SyncTop.app
   ```
   SyncTop will appear directly in your macOS Menu Bar!

### Running Tests

```bash
swift run SyncTopTests
```

---

## ⚙️ Configuration & Storage

SyncTop stores your profile configuration and sync run history cleanly in standard macOS Application Support:
- `~/Library/Application Support/SyncTop/profiles.json`
- `~/Library/Application Support/SyncTop/history.json`

Because configuration is stored as readable JSON, you can also easily version-control or inspect your sync profiles.

---

## 🤝 Contributing

Contributions are very welcome!
1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Ensure all tests pass (`swift run SyncTopTests`)
4. Commit your changes (`git commit -m 'Add awesome feature'`)
5. Push to the branch (`git push origin feature/my-feature`)
6. Open a Pull Request

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
