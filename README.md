# Iris Editor

A native **Markdown** editor for macOS, built with **SwiftUI**, **AppKit**, and **Swift 6**.

Iris Editor is a focused `.md` editing surface: Markdown syntax highlighting, a rendered
preview, Markdown formatting shortcuts, line numbers, find & replace, go-to-line, live
document stats, and Liquid Glass surfaces on native macOS window chrome — with no
Electron, no dependencies, and no project bloat.

## Features

- Native document window: real title bar, unified toolbar, proxy icon, edited dot,
  movable-by-background, and a translucent behind-window material instead of painted chrome
- **Liquid Glass** surfaces built on `NSGlassEffectView`; on macOS 27 (Golden Gate)
  the editor card and find bar opt into `effectIsInteractive` for pointer-responsive glass
- **Markdown-first**: new documents default to `.md`, open/save panels target Markdown,
  and the gutter/editor highlight headings, emphasis, links, lists, and fenced code
- **Markdown preview** — a read-only rendered view (`AttributedString(markdown:)`)
  toggled from the toolbar or `⇧⌘P`
- **Markdown formatting** — Bold (`⌘B`), Italic (`⌘I`), Inline Code (`⌘K`),
  Strikethrough, Heading, Bulleted List, and Block Quote via the *Format* menu or a
  quick-format toolbar
- **Markdown-aware statistics** — word and character counts strip syntax markers so the
  status bar reports visible content
- TextKit editor with an `NSRulerView` line-number gutter, current-line highlight,
  and live find-match highlighting
- **Find & Replace** — case-insensitive, live match highlighting, replace current / replace all
- **Go to Line** — jump directly to any line number
- Status bar with live cursor position, line count, word count, character count, and file size
- Dirty-state indicator in the title bar and status bar
- Configurable settings: font family, font size, tab width, line numbers, word wrap,
  current-line highlight — persisted to `UserDefaults`
- Native `Settings` scene (⌘,), File / Edit / View / Model / Format menus, and the standard About panel

## Requirements

| | |
|---|---|
| OS | macOS 26 or later; macOS 27 “Golden Gate” recommended |
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
| `⌘+` / `⌘-` / `⌘0` | Zoom in / out / reset |
| `⌘,` | Settings |
| `⌘B` | Bold |
| `⌘I` | Italic |
| `⌘K` | Inline Code |
| `⇧⌘P` | Toggle Markdown Preview |

## Project Structure

```
IrisEditor/
├── Package.swift                     # SwiftPM manifest (macOS 26, Swift 6 language mode)
├── Sources/IrisEditor/
│   ├── IrisEditorApp.swift           # @main App, Commands, Settings scene, AppDelegate
│   ├── Managers/
│   │   └── AppState.swift            # ObservableObject: document ops, find/replace, settings, Markdown formats
│   ├── Models/
│   │   ├── EditorDocument.swift      # Text, file URL, dirty flag, Markdown-aware stats
│   │   ├── EditorSettings.swift      # Codable settings + UserDefaults persistence
│   │   ├── MarkdownSupport.swift     # Markdown file types, plain-text stripping, syntax highlighter
│   │   └── TextSearch.swift          # Pure search + line-index helpers (unit tested)
│   └── Views/
│       ├── ContentView.swift         # Root layout, editor card, Markdown toolbar, native toolbar
│       ├── WindowChrome.swift        # Window configuration + NSGlassEffectView wrappers
│       ├── TextEditorView.swift      # NSTextView editor, line-number ruler, highlights, Markdown formatting
│       ├── MarkdownPreviewView.swift # Read-only rendered Markdown preview
│       ├── FindReplacePanel.swift    # Glass find/replace and go-to-line bar
│       ├── StatusBarView.swift       # Cursor / counts / size readout
│       └── SettingsView.swift        # Native grouped Settings form
└── Tests/IrisEditorTests/
    └── IrisEditorTests.swift         # Swift Testing suite
```

## Architecture Notes

- **`AppState`** is a `@MainActor` singleton injected via `EnvironmentObject`. All document,
  find, and settings mutations flow through it.
- **`EditorDocument`** is an `ObservableObject` reference type, so swapping documents
  (New / Open) rebinds the editor cleanly instead of mutating shared state.
- **Window chrome is real macOS chrome.** `WindowConfigurator` sets the window title,
  represented URL, edited state, a unified native toolbar, and a non-opaque window backed by
  `NSVisualEffectView` (`.underWindowBackground`, behind-window blending).
- **Glass is real Liquid Glass.** `GlassBackdrop` wraps `NSGlassEffectView`; on macOS 27 it
  enables `effectIsInteractive` under an availability check while the deployment target stays
  at macOS 26.
- **Find/replace** recomputes matches through a debounced Combine pipeline (150 ms) that
  re-subscribes when the document changes, then broadcasts `NSRange`s via `NotificationCenter`
  for the AppKit text view to highlight.
- **The editor is AppKit (`NSTextView`)** wrapped in `NSViewRepresentable`, because SwiftUI's
  `TextEditor` does not expose line numbers, gutter rendering, or per-range highlighting.
  Line numbers are an `NSRulerView` so the gutter scrolls with the text without reparenting
  TextKit views.
- **Search and line math** live in `TextSearch.swift` as pure functions, so matching and
  line-number mapping are covered by unit tests without touching AppKit.
- **Markdown syntax highlighting** lives in `MarkdownSupport.swift`. It produces
  `(NSRange, token)` pairs that the text view paints as temporary attributes, so user text
  and undo history are never mutated. Word/character stats run the same source through
  `MarkdownPlainText` to strip formatting markers before counting.
- **Markdown formatting** is issued as a notification from `AppState` and serviced by the
  text view (`toggleMarkdownFormat`), which wraps/unwraps the selection in the requested
  marker without replacing user content.

## Status

Iris Editor is an early work-in-progress. Markdown editing, syntax highlighting, preview,
formatting, find/replace, go-to-line, settings, and the status bar are functional.

**Not yet implemented:** GPT-2 autocomplete. The original Python prototype used
`transformers`/`torch`; running it in Swift would require converting the model to Core ML.
The menu items exist but are disabled and surface an explanatory alert. See
[`docs/legacy-readme-pyqt5.md`](docs/legacy-readme-pyqt5.md) for the archived Python/PyQt5
prototype notes.

## License

No license file yet — all rights reserved by Apollo Studio Moonshot unless stated otherwise.
