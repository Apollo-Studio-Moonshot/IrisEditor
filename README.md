# Iris Editor

A lightweight, native plain-text editor for macOS, built with **SwiftUI** and **Swift 6**.

Iris Editor is a focused `.txt` editing surface: line numbers, find & replace, go-to-line,
live document stats, and a Liquid Glass–style dark interface — with no Electron, no
dependencies, and no project bloat.

## Features

- Native SwiftUI / AppKit app (Swift Package Manager executable, no Xcode project required)
- Plain-text editing with a monospaced, line-numbered editor
- **Find & Replace** — case-insensitive, live match highlighting, replace current / replace all
- **Go to Line** — jump directly to any line number
- Status bar with live line count, word count, character count, and file size
- Dirty-state indicator in both the toolbar and status bar
- Configurable settings: font family, font size, tab width, line numbers, word wrap,
  current-line highlight — persisted to `UserDefaults`
- Animated Liquid Glass background with hidden title bar (traffic lights inline)
- Standard macOS File / Edit menu wiring, including native About panel

## Requirements

| | |
|---|---|
| OS | macOS 26 or later |
| Toolchain | Swift 6.3+ (Xcode 26 *or* Command Line Tools) |

No third-party packages, no Package.swift dependencies.

## Build & Run

```sh
git clone https://github.com/Apollo-Studio-Moonshot/IrisEditor.git
cd IrisEditor
swift run IrisEditor
```

Or from the repository root:

```sh
swift build          # debug build
swift build -c release
swift run            # build and launch
```

The built binary lands in `.build/debug/IrisEditor` (or `.build/release/IrisEditor`).

### Tests

```sh
swift test
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘N` | New document |
| `⌘O` | Open… |
| `⌘S` | Save |
| `⇧⌘S` | Save As… |
| `⌘F` | Find & Replace |
| `⌘G` | Go to Line… |
| `⌘,` | Settings |

## Project Structure

```
IrisEditor/
├── Package.swift                     # SwiftPM manifest (macOS 26, Swift 6 language mode)
├── Sources/IrisEditor/
│   ├── IrisEditorApp.swift           # @main App, menu commands, AppDelegate
│   ├── Managers/
│   │   └── AppState.swift            # ObservableObject: document ops, find/replace, settings
│   ├── Models/
│   │   ├── EditorDocument.swift      # Text, file URL, dirty flag, stats
│   │   └── EditorSettings.swift      # Codable settings + UserDefaults persistence
│   └── Views/
│       ├── ContentView.swift         # Root layout + animated gradient background
│       ├── TextEditorView.swift      # NSTextView-backed editor (line numbers, highlighting)
│       ├── ToolbarBar.swift          # Custom inline toolbar
│       ├── StatusBarView.swift       # Line / word / char / size readout
│       ├── FindReplacePanel.swift    # Floating find, replace, go-to-line panel
│       └── SettingsView.swift        # Settings window
└── Tests/IrisEditorTests/
    └── IrisEditorTests.swift         # Swift Testing suite
```

## Architecture Notes

- **`AppState`** is a `@MainActor` singleton injected via `EnvironmentObject`. All document,
  find, and settings mutations flow through it.
- **`EditorDocument`** is an `ObservableObject` reference type, so swapping documents
  (New / Open) rebinds the editor cleanly instead of mutating shared state.
- **Find/replace** recomputes matches through a debounced Combine pipeline (150 ms) that
  re-subscribes when the document changes, then broadcasts `NSRange`s via `NotificationCenter`
  for the AppKit text view to highlight.
- **The editor is AppKit (`NSTextView`)** wrapped in `NSViewRepresentable`, because SwiftUI's
  `TextEditor` does not expose line numbers, gutter rendering, or per-range highlighting.

## Status

Iris Editor is an early work-in-progress. Editor, find/replace, go-to-line, settings, and
status bar are functional.

**Not yet implemented:** GPT-2 autocomplete. The original Python prototype used
`transformers`/`torch`; running it in Swift would require converting the model to Core ML.
The menu items exist but are disabled and surface an explanatory alert. See
[`docs/legacy-readme-pyqt5.md`](docs/legacy-readme-pyqt5.md) for the archived Python/PyQt5
prototype notes.

## License

No license file yet — all rights reserved by Apollo Studio Moonshot unless stated otherwise.
