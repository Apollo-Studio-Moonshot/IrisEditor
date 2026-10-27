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
- **Markdown preview** — a native renderer for the full Markdown Guide basic syntax:
  ATX and Setext headings, hard/soft line breaks, all emphasis combinations, nested
  block quotes, nested ordered/unordered lists with paragraphs/quotes/code, inline and
  indented/fenced code, rules, inline/reference/autolink links, images (local and remote),
  escaping, inline HTML, HTML blocks (tables in HTML markup render as real tables), pipe
  **tables**, and nesting anywhere — cycling
  through *source → split → preview* from the toolbar or `⌥⌘P`
- **Editor tabs** — multiple documents open as tabs in one window: `⌘T` opens a new tab,
  `⌘W` closes the current tab (prompting to save; the last tab closes the window),
  `⇧⌘[` / `⇧⌘]` cycle tabs, and
  opening a file already shown focuses its existing tab
- **Smart Markdown continuation** — Return continues bulleted, ordered, task, and quoted
  lines with the right marker (incrementing ordered numbers), and Return on an empty item
  exits the list instead of leaving a stray marker
- **HTML export** — File ▸ Export as HTML… (`⇧⌘E`) writes a standalone, appearance-aware
  HTML file using the same parser as the in-app preview
- **Animated tab strip** — tabs scale and fade in/out as they open and close, the active
  Liquid Glass pill slides between tabs, and the strip auto-scrolls to keep the active tab
  visible
- **Obsidian-style navigation** — a fuzzy **Quick Switcher** (`⌘P`) for open tabs and recent
  files, a searchable **Command Palette** (`⇧⌘P`), and a live **Outline** sidebar (`⇧⌘O`)
  covering ATX and Setext headings
- **Wiki links** — `[[Note]]`, `[[Note|Alias]]`, and `[[Note#Heading]]` links are highlighted
  in the editor and clickable in the preview; links resolve to open tabs, recent files, or
  notes beside the current document, and missing notes are created on demand
- **Recent files and drag-and-drop** — File ▸ Open Recent, plus dropping `.md` files on the
  window opens them as tabs
- **Seamless saves** — dirty documents with a file URL auto-save two seconds after typing
  stops; the cursor and scroll position are preserved per tab
- **Markdown formatting** — Bold (`⌘B`), Italic (`⌘I`), Inline Code (`⌘K`),
  Strikethrough, Heading, Bulleted List, and Block Quote via the *Format* menu or a
  quick-format toolbar
- **Markdown-aware statistics** — word and character counts strip syntax markers so the
  status bar reports visible content
- TextKit editor with an `NSRulerView` line-number gutter, current-line highlight,
  and live find-match highlighting
- **Find & Replace** — case-insensitive by default with optional *Match Case* and
  *Whole Word* toggles, live match highlighting, replace current / replace all
- **Go to Line** — jump directly to any line number
- Status bar with live cursor position, line count, word count, character count, and file size
- Dirty-state indicator in the title bar and status bar
- Configurable settings: font family, font size, tab width, line numbers, word wrap,
  current-line highlight — persisted to `UserDefaults`
- Native `Settings` scene (⌘,), File / Edit / View / Navigate / Model / Format menus, and the standard About panel

## Requirements

| | |
|---|---|
| OS | macOS 26 or later; macOS 27 “Golden Gate” supported and build-verified against the macOS 27 SDK |
| Toolchain | Swift 6.3+ (Xcode 26 *or* Command Line Tools) |

No third-party packages, no Package.swift dependencies.

## Build & Run

### Xcode

```sh
git clone https://github.com/Apollo-Studio-Moonshot/IrisEditor.git
cd IrisEditor
open IrisEditor.xcodeproj
```

Select the **IrisEditor** scheme and run. The project includes the app target, the
**IrisEditorTests** unit-test target, a shared scheme, `Support/Info.plist`, and an asset
catalog with the app icon and accent color. For a command-line build:

```sh
xcodebuild -project IrisEditor.xcodeproj -scheme IrisEditor -configuration Debug \
  -derivedDataPath .build/xcode-derived build
```

### Swift Package Manager

```sh
swift run IrisEditor
```

Or from the repository root:

```sh
swift build          # debug build
swift build -c release
swift run            # build and launch
```

The built binary lands in `.build/debug/IrisEditor` (or `.build/release/IrisEditor`).
`scripts/build_app_bundle.sh` wraps the release binary in a signed `.app` using the same
`Support/Info.plist` as the Xcode target.

### Tests

In Xcode, press `⌘U` (the shared scheme includes the test target). From the command line:

```sh
swift test
# or
xcodebuild -project IrisEditor.xcodeproj -scheme IrisEditor -derivedDataPath .build/xcode-derived test
```

> Note: with Command Line Tools only (no full Xcode), the Swift Testing macro plugin is
> not auto-discovered. Run tests with an explicit plugin path instead:
> `swift test -Xswiftc -load-plugin-library -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"`

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘T` | New tab |
| `⌘O` | Open… (multi-select) |
| `⌘S` | Save |
| `⇧⌘S` | Save As… |
| `⇧⌘E` | Export as HTML… |
| `⌘W` | Close Tab (closes the window on the last tab) |
| `⇧⌘T` | Reopen Closed Tab |
| `⇧⌘[` / `⇧⌘]` | Previous / Next Tab |
| `⌘P` | Quick Switcher |
| `⇧⌘P` | Command Palette |
| `⇧⌘O` | Toggle Outline |
| `⌘F` | Find & Replace |
| `⌘G` | Go to Line… |
| `⌘=` / `⌘-` / `⌘0` | Zoom in / out / reset |
| `⌘,` | Settings |
| `⌘B` | Bold |
| `⌘I` | Italic |
| `⌘K` | Inline Code |
| `⌥⌘P` | Cycle Source / Split / Preview |
| `Return` | Continue the current list/quote item |

## Project Structure

```
IrisEditor/
├── Package.swift                     # SwiftPM manifest (macOS 26, Swift 6 language mode)
├── IrisEditor.xcodeproj/             # Xcode app + unit-test targets, shared scheme
├── Support/
│   ├── Info.plist                    # Bundle metadata, Markdown document types
│   └── Assets.xcassets/              # App icon and Iris accent color
├── Sources/IrisEditor/
│   ├── IrisEditorApp.swift           # @main App, Commands, Settings scene, AppDelegate
│   ├── Managers/
│   │   └── AppState.swift            # ObservableObject: document ops, find/replace, settings, Markdown formats
│   ├── Models/
│   │   ├── EditorDocument.swift      # Text, file URL, dirty flag, Markdown-aware stats
│   │   ├── EditorSettings.swift      # Codable settings + UserDefaults persistence
│   │   ├── FuzzyMatch.swift          # Fuzzy scoring for the quick switcher / palette
│   │   ├── MarkdownBlocks.swift      # Recursive block parser for the preview
│   │   ├── MarkdownEditing.swift     # List/quote continuation logic for Return
│   │   ├── MarkdownHTMLExport.swift  # Standalone HTML export renderer
│   │   ├── MarkdownInline.swift      # Inline parser (emphasis, code, links, wiki links…)
│   │   ├── MarkdownOutline.swift     # ATX/Setext heading extraction for the outline
│   │   ├── MarkdownFormatting.swift  # Grapheme-safe wrap/unwrap + line-prefix formatting
│   │   ├── MarkdownSupport.swift     # Markdown file types, plain-text stripping, highlighter
│   │   ├── RecentFiles.swift         # Persisted recent-file history
│   │   └── TextSearch.swift          # Pure search + line-index helpers (unit tested)
│   └── Views/
│       ├── ContentView.swift         # Root layout, editor card, overlays, native toolbar
│       ├── TabBarView.swift          # Animated document tabs with glass active pill
│       ├── CommandPaletteView.swift  # Obsidian-style command palette
│       ├── QuickSwitcherView.swift   # Fuzzy open-tab / recent-file switcher
│       ├── DocumentOutlineView.swift # Live heading outline sidebar
│       ├── WindowChrome.swift        # Window configuration + NSGlassEffectView wrappers
│       ├── TextEditorView.swift      # NSTextView editor, line-number ruler, highlights
│       ├── MarkdownPreviewView.swift # Read-only rendered Markdown preview
│       ├── FindReplacePanel.swift    # Glass find/replace and go-to-line bar
│       ├── StatusBarView.swift       # Cursor / counts / size readout
│       └── SettingsView.swift        # Native grouped Settings form
├── Tests/IrisEditorTests/
│   ├── EditingAndExportTests.swift   # Continuation, statistics, offsets, HTML export
│   ├── IrisEditorTests.swift         # Markdown, search, and formatting tests
│   └── WorkspaceTests.swift          # Fuzzy matching, outline, wiki links, recents
└── scripts/
    └── build_app_bundle.sh           # Wrap the release binary in a signed .app
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
  at macOS 26, so the same binary runs on macOS 26 and Golden Gate.
- **Tabs animate as documents come and go.** Insertion/removal transitions live on each tab
  item, the active glass pill uses `matchedGeometryEffect`, and the strip scrolls the active
  tab into view. Tab mutations are wrapped in `withAnimation` in `AppState`.
- **Quick switcher and command palette** are pure SwiftUI overlays. `FuzzyMatch` scores
  subsequence matches with word-boundary and prefix bonuses, and `RecentFiles` persists a
  20-entry history in `UserDefaults`.
- **Wiki links** are parsed by `MarkdownInlineParser` into `.wikiLink(target:label:)`, tinted
  by the syntax highlighter, rendered as accent-colored links in the preview, and resolved by
  `AppState.openWikiLink` (open tab → recent file → sibling note → create sibling note).
  `ContentView` intercepts the preview's `iriseditor://wiki` URLs with `OpenURLAction`.
- **Outline parsing** is pure and unit-tested in `MarkdownOutline`, which handles ATX and
  Setext headings, ignores fenced code, and flattens inline Markdown for the sidebar.
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
  marker without replacing user content. Formatting and snippet insertion go through
  `NSTextView.insertText(_:replacementRange:)` so they participate in undo/redo.
- **Smart Return** is centralized in `MarkdownEditing`, a pure helper that detects bullet,
  ordered, task-list, and nested block-quote markers. `IrisTextView.insertNewline` applies
  the decision; an empty item removes its marker and exits the container.
- **HTML export** reuses the preview's block and inline parsers through
  `MarkdownHTMLExport`, escaping text and raw HTML so exported files are safe to open in a
  browser and look consistent with the in-app preview.

## Status

Iris Editor is an early work-in-progress. Markdown editing, syntax highlighting, preview,
formatting, smart list continuation, HTML export, find/replace, go-to-line, settings,
animated tabs, the quick switcher, command palette, outline sidebar, wiki links, recent
files, and the status bar are functional.

**Not yet implemented:** GPT-2 autocomplete. The original Python prototype used
`transformers`/`torch`; running it in Swift would require converting the model to Core ML.
The *Load GPT-2 Model…* menu item surfaces an explanatory alert; *Trigger Autocomplete*
remains disabled until the model ships. See
[`docs/legacy-readme-pyqt5.md`](docs/legacy-readme-pyqt5.md) for the archived Python/PyQt5
prototype notes.

## License

No license file yet — all rights reserved by Apollo Studio Moonshot unless stated otherwise.
