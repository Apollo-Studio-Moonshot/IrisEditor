# Iris Editor

A native **Markdown** editor for macOS, built with **SwiftUI**, **AppKit**, and **Swift 6**.

Iris Editor is a native Markdown editor **and** a local-first vault reader: syntax
highlighting, a rendered preview, formatting shortcuts, find & replace, live stats,
Liquid Glass window chrome — plus backlinks, unlinked mentions, a link graph, daily
notes, templates, properties, version history, and on-device AI. No Electron, no
dependencies, no project bloat, and your notes stay plain `.md` files on disk.

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
  through *source → split → preview* from the toolbar or `⌥⌘P`. Obsidian syntax is
  covered too: `==highlight==` renders with a theme-aware backing colour, and
  **callouts** (`> [!note]`, `tip`, `warning`, `danger`, `bug`, `quote`, … with every
  Obsidian alias) render as tinted icon cards that fold when written `> [!note]-`.
  Preview parsing is debounced and cached, so typing in a long note no longer re-parses
  the whole document on every keystroke
- **Footnotes** — `[^label]` references render as numbered superscripts and collect into
  a footnote list at the end of the preview; `[^label]: text` definitions support
  indented continuation lines and are never shown inline. HTML export emits a matching
  `<section class="footnotes">` with backlinks
- **Editable transclusion** — a paragraph that is only `![[Note]]` expands the embedded
  note in place, with its own tables, callouts, code, wikilinks, and footnote numbering;
  `![[Note#Heading]]` embeds one section and `![[Note#^block]]` one block, images and
  `![[file.png|320]]` render inline, and nesting stops at two levels so a self-referential
  vault cannot lock up the preview. Clicking an embed's title opens the source note
- **Mermaid and math** — ` ```mermaid ` fenced blocks render as live flowcharts, and
  `$…$`, `$$…$$`, `\(…\)`, and `\[…\]` render through a native LaTeX layout engine
- **Code highlighting in preview and export** — fenced code is tokenized by a shared
  highlighter, so the preview, HTML export, and PDF all agree
- **Editor tabs** — multiple documents open as tabs in one window: `⌘T` opens a new tab,
  `⌘W` closes the current tab (prompting to save; the last tab closes the window),
  `⇧⌘[` / `⇧⌘]` cycle tabs, and
  opening a file already shown focuses its existing tab
- **Smart Markdown continuation** — Return continues bulleted, ordered, task, and quoted
  lines with the right marker (incrementing ordered numbers), and Return on an empty item
  exits the list instead of leaving a stray marker
- **Export and print** — File ▸ Export as HTML… (`⇧⌘E`), Export as PDF… (`⌥⌘E`),
  and Export as RTF… write appearance-aware output using the same parser as the preview;
  File ▸ Print… (`⌥⇧⌘P`) sends paginated, print-styled output through the native print panel
- **Themes** — System / Light / Dark / High Contrast window appearance, eight built-in
  accents plus a custom color picker, and System / Paper / Sepia / Midnight preview themes
- **Vim and Emacs keymaps** — opt into modal Normal / Insert / Visual / `:` editing with
  counts, motions, `dd`/`cc`/`yy`, paste, undo, and `:w` / `:q` / `:wq`, or classic
  Emacs Control/Option navigation, kill, and yank
- **Animated tab strip** — tabs scale and fade in/out as they open and close, the active
  Liquid Glass pill slides between tabs, and the strip auto-scrolls to keep the active tab
  visible
- **Obsidian-style navigation** — a fuzzy **Quick Switcher** (`⌘P`) for open tabs and recent
  files, a searchable **Command Palette** (`⇧⌘P`), and a live **Outline** sidebar (`⇧⌘O`)
  covering ATX and Setext headings
- **Wiki links** — `[[Note]]`, `[[Note|Alias]]`, and `[[Note#Heading]]` links are highlighted
  in the editor and clickable in the preview; links resolve to open tabs, recent files, or
  notes beside the current document, and missing notes are created on demand
- **Vault sidebar** — five panes driven by one scan of the vault: files (folder tree),
  outline, tags (`#tag` counts), backlinks, and a local link graph
- **Backlinks and unlinked mentions** — every `[[note]]` pointing at the current note is
  listed with its line and excerpt, and prose that mentions the title without linking it
  is listed separately; both jump straight to the line. Mentions inside fenced code and
  on already-linked lines are excluded, and a progress toggle switches the graph between
  the current note's neighbourhood and the whole vault
- **Daily notes and templates** — `⇧⌘D` opens (or creates) today's note under
  `Daily Notes/yyyy-MM-dd.md`, and *Insert Template* applies any file from the vault's
  `Templates/` folder
- **Properties** — YAML frontmatter renders as a readable card in the preview instead of
  raw `---` fences, with tag chips, dates, and booleans handled
- **Version history** — every save records a snapshot (the newest 25 per document) and
  *Navigate ▸ Version History* previews and restores earlier revisions
- **Spotlight integration** — vault notes are indexed with CoreSpotlight so they appear in
  Spotlight search and can be opened from there
- **Quick capture everywhere** — a menu-bar `MenuBarExtra` capture window, the
  `iriseditor://capture?text=…` URL, `iriseditor://new?text=…`, and an *Open Markdown in
  Iris* **Services** entry for selected text or files in any app
- **On-device and remote AI** — writing-assistant commands (inline completion, rewrite
  selection, summarize, suggest title/tags) run through Apple Intelligence Foundation
  Models when available, or a provider configured in Settings ▸ AI
- **Vault search operators** — the full-vault search field (`⇧⌘F`) understands
  `tag:#idea`, `path:daily`, `file:meeting`, `match-case:`, quoted values, and `-` exclusions,
  so a filter-only query like `tag:project -path:archive` lists matching notes
- **Recent files and drag-and-drop** — File ▸ Open Recent, plus dropping `.md` files on the
  window opens them as tabs
- **Seamless saves** — dirty documents with a file URL auto-save two seconds after typing
  stops; the cursor and scroll position are preserved per tab
- **Markdown formatting** — Bold (`⌘B`), Italic (`⌘I`), Inline Code (`⌘K`),
  Strikethrough, Heading, Bulleted List, and Block Quote via the *Format* menu or a
  quick-format toolbar
- **Markdown-aware statistics** — word and character counts strip syntax markers so the
  status bar reports visible content
- **Chinese, Japanese, and Korean text** — the editor defers to the system input method
  while text is composing (candidate arrows, Return, Tab, and Escape work as expected),
  counts each CJK character as a word, and moves Vim `w`/`b`/`e` by CJK character
- TextKit editor with an `NSRulerView` line-number gutter, current-line highlight,
  and live find-match highlighting
- **Find & Replace** — case-insensitive by default with optional *Match Case* and
  *Whole Word* toggles, live match highlighting, replace current / replace all
- **Go to Line** — jump directly to any line number
- Status bar with live cursor position, line count, word count, character count, and file size
- Dirty-state indicator in the title bar and status bar
- Configurable settings: font family, font size, tab width, line numbers, word wrap,
  current-line highlight — persisted to `UserDefaults`
- **Plugin API** — drop a JavaScript folder or `.js` file into
  `~/Library/Application Support/IrisEditor/Plugins` to add commands, exporters, and
  theme-switching commands; see [`docs/plugins.md`](docs/plugins.md)
- Native `Settings` scene (⌘,) split into Editor, Appearance, Writing, AI, Keys, Plugins,
  and Advanced tabs, plus File / Edit / View / Navigate / Plugins / Model / Format menus
  and the standard About panel

## Requirements

| | |
|---|---|
| OS | macOS 27 “Golden Gate” or later, built against the macOS 27 SDK |
| Toolchain | Swift 6.4+ (Xcode 27 *or* Command Line Tools) |

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
xcodebuild -project IrisEditor.xcodeproj -scheme IrisEditor -configuration Debug build
```

> Keep DerivedData out of the repository. Xcode resolves a DerivedData tree inside the
> package root as a package target and its `.build/artifacts` as a binary artifact, so
> `GenerateAssetSymbols` fails with *"You don't have permission to save the file
> GeneratedAssetSymbols.swift"* (`Operation not permitted`) and the link step follows.
> `swift build` owns `.build/` at the root, so point `-derivedDataPath` outside the
> repository instead, and run `scripts/clean_build_inputs.sh` to relocate a tree that is
> already there.

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
xcodebuild -project IrisEditor.xcodeproj -scheme IrisEditor test
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
| `⌥⌘E` | Export as PDF… |
| `⌥⇧⌘P` | Print… |
| `⌘W` | Close Tab (closes the window on the last tab) |
| `⇧⌘T` | Reopen Closed Tab |
| `⇧⌘[` / `⇧⌘]` | Previous / Next Tab |
| `⌘P` | Quick Switcher |
| `⇧⌘P` | Command Palette |
| `⇧⌘O` | Toggle Outline |
| `⇧⌘F` | Search the whole vault |
| `⇧⌘D` | Open (or create) today's daily note |
| `⇧⌘N` | New note in the vault |
| `⌘F` | Find & Replace |
| `⌘G` | Go to Line… |
| `⌘=` / `⌘-` / `⌘0` | Zoom in / out / reset |
| `⌘,` | Settings |
| `⌘B` | Bold |
| `⌘I` | Italic |
| `⌘K` | Inline Code |
| `⌥⌘P` | Cycle Source / Split / Preview |
| `Return` | Continue the current list/quote item |

Vim mode adds its own modal bindings (`h j k l w b e 0 $ gg G`, `i a I A o O`,
`x dd cc yy d/c/y + motion`, `p P u Ctrl-R`, `v V`, and `:w` / `:q` / `:wq`). Emacs mode
adds `C-a`, `C-e`, `C-f`, `C-b`, `C-n`, `C-p`, `C-d`, `C-k`, `C-y`, `C-w`, `C-s`, and
`M-f` / `M-b` / `M-d`.

## Project Structure

```
IrisEditor/
├── Package.swift                     # SwiftPM manifest (macOS 27, Swift 6 language mode)
├── IrisEditor.xcodeproj/             # Xcode app + unit-test targets, shared scheme
├── Support/
│   ├── Info.plist                    # Bundle metadata, Markdown document types
│   └── Assets.xcassets/              # App icon and Iris accent color
├── Sources/IrisEditor/
│   ├── IrisEditorApp.swift           # @main App, Commands, Settings scene, AppDelegate
│   ├── Managers/
│   │   ├── AppState.swift            # ObservableObject: documents, vault, find, settings, AI, plugins
│   │   └── SpotlightIndexer.swift    # CoreSpotlight indexing for vault notes
│   ├── Models/
│   │   ├── AIAssistant.swift         # Writing-assistant prompts over the selected provider
│   │   ├── AIProvider.swift          # On-device Foundation Models or remote provider config
│   │   ├── CJKText.swift             # CJK-aware word counting and Vim motion boundaries
│   │   ├── CodeSyntaxHighlighter.swift # Shared tokenizer for preview, HTML, and PDF
│   │   ├── DraftStore.swift          # Crash-recovery drafts for unsaved buffers
│   │   ├── EditorDocument.swift      # Text, file URL, dirty flag, Markdown-aware stats
│   │   ├── EditorSettings.swift      # Codable settings, appearance, themes, keymap + persistence
│   │   ├── FuzzyMatch.swift          # Fuzzy scoring for the quick switcher / palette
│   │   ├── HTMLToMarkdown.swift      # Paste-as-Markdown converter
│   │   ├── KeybindingCommand.swift   # Remappable command list and shortcut parsing
│   │   ├── LaTeXMathRenderer.swift   # Native `$…$` / `$$…$$` layout
│   │   ├── MarkdownBlocks.swift      # Recursive block parser (+ frontmatter, footnotes)
│   │   ├── MarkdownEditing.swift     # List/quote continuation logic for Return
│   │   ├── MarkdownFootnotes.swift   # Footnote numbering in reference order
│   │   ├── MarkdownFormatting.swift  # Grapheme-safe wrap/unwrap + line-prefix formatting
│   │   ├── MarkdownFrontmatter.swift # YAML frontmatter parsing for the properties card
│   │   ├── MarkdownHTMLExport.swift  # Standalone HTML export renderer
│   │   ├── MarkdownInline.swift      # Inline parser (emphasis, code, links, wiki links, footnotes, embeds)
│   │   ├── MarkdownOutline.swift     # ATX/Setext heading extraction for the outline
│   │   ├── MarkdownSupport.swift     # Markdown file types, plain-text stripping, highlighter
│   │   ├── MermaidRenderer.swift     # `mermaid` flowchart → SwiftUI diagram
│   │   ├── RecentFiles.swift         # Persisted recent-file history
│   │   ├── SessionStore.swift        # Restores tabs, cursors, and view mode at launch
│   │   ├── TextSearch.swift          # Pure search + line-index helpers (unit tested)
│   │   ├── Transclusion.swift        # `![[…]]` request parsing, section/block slicing
│   │   ├── Vault.swift               # Scanning, folders, tags, backlinks, mentions, graph, search
│   │   ├── VersionHistoryStore.swift # Snapshot history per document path
│   │   └── VimEngine.swift           # Pure modal-editing state machine (unit tested)
│   ├── Services/
│   │   ├── AIProviderClient.swift    # HTTP/Foundation Models client for the writing assistant
│   │   ├── LocalizableStrings.swift  # L10n helpers for every user-facing string
│   │   ├── MarkdownPDFExporter.swift # Offscreen WKWebView PDF generation and printing
│   │   ├── MarkdownRTFExporter.swift # HTML → RTF export bridge
│   │   └── PluginHost.swift          # JavaScriptCore plugin discovery, commands, exporters
│   └── Views/
│       ├── CommandPaletteView.swift  # Obsidian-style command palette
│       ├── ContentView.swift         # Root layout, editor card, overlays, native toolbar
│       ├── DocumentOutlineView.swift # Live heading outline sidebar
│       ├── FindReplacePanel.swift    # Glass find/replace and go-to-line bar
│       ├── MarkdownPreviewView.swift # Rendered preview: blocks, transclusions, footnotes
│       ├── MarkdownPropertiesCard.swift # Frontmatter as a readable card
│       ├── QuickCaptureView.swift    # Menu-bar quick capture window
│       ├── QuickSwitcherView.swift   # Fuzzy open-tab / recent-file switcher
│       ├── SettingsView.swift        # Settings: Editor, Appearance, Writing, AI, Keys, Plugins, Advanced
│       ├── SidebarView.swift         # Files, outline, tags, backlinks + mentions, graph
│       ├── StatusBarView.swift       # Cursor / counts / size readout
│       ├── TabBarView.swift          # Animated document tabs with glass active pill
│       ├── TextEditorView.swift      # NSTextView editor, line-number ruler, highlights
│       ├── VaultSearchView.swift     # Full-vault search with operators
│       ├── VersionHistoryView.swift  # Snapshot list and restore
│       ├── WikiSuggestionBar.swift   # `[[` / `![[` autocomplete
│       └── WindowChrome.swift        # Window configuration + NSGlassEffectView wrappers
├── Tests/IrisEditorTests/
│   ├── EditingAndExportTests.swift   # Continuation, statistics, offsets, HTML export
│   ├── EditorModesTests.swift        # Vim motions, edits, and theme/settings decoding
│   ├── IrisEditorTests.swift         # Markdown, search, and formatting tests
│   ├── ObsidianParityTests.swift     # Highlights, callouts, tables, quoting
│   ├── TransclusionAndMentionsTests.swift # Footnotes, embeds, slicing, unlinked mentions
│   ├── VaultQueryTests.swift         # Search operators
│   ├── WorkspaceTests.swift          # Fuzzy matching, outline, wiki links, recents
│   └── Regression*Tests.swift        # Fixed bugs kept fixed
├── docs/
│   └── plugins.md                    # Plugin manifest, command, exporter, and theme API
├── research/
│   ├── obsidian-feature-inventory.md # Verified Obsidian 1.14 feature inventory
│   └── positioning.md                # Parity ledger and differentiation bets
└── scripts/
    ├── build_app_bundle.sh           # Wrap the release binary in a signed .app
    └── clean_build_inputs.sh         # Relocate DerivedData left inside the project
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
  enables `effectIsInteractive` under an availability check while the deployment target
  remains macOS 27, so the status bar mode badge, tab pill, panels, and editor card all use
  pointer-responsive Golden Gate glass.
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
- **Transclusion stays a view concern.** `MarkdownInlineParser` emits
  `.embed(target:label:)`, `TransclusionRequest` splits `Note#Heading` / `Note#^block`,
  and `TransclusionSlicer` cuts the requested section or block. The preview reads a
  resolver closure out of the environment (`ContentKey`-style `EnvironmentKey`), so the
  view never touches the file system; `ContentView` injects
  `appState.transclusion(_:relativeTo:)`, which resolves the note through
  `VaultScanner.resolve` and guards against self-embeds, unreadable files, and nesting
  deeper than two levels. Embedded blocks render through the same `MarkdownBlockView`
  with the embedded document's own link definitions and footnote numbering
- **Footnotes are numbered from references, not definitions.** `MarkdownFootnoteIndex`
  walks the parsed blocks in reading order (including list items, quotes, and table
  cells) and produces both the number map and the ordered footnote list, so the preview,
  the HTML export, and any future exporter share one numbering source
- **Unlinked mentions reuse the backlink graph.** `VaultScanner.unlinkedMentions(of:in:)`
  builds the same alias set as `backlinks(to:in:)`, skips fenced code blocks and lines
  that already contain `[[`, masks inline code, and matches on word boundaries — so
  "Design notesmith" is not a mention of "Design notes"
- **The graph is one function, two scopes.** `VaultScanner.graph(around:in:depth:highlighting:)`
  takes a note for a local neighbourhood and `nil` for the whole vault (capped at 60
  nodes), while `highlighting:` still marks the open note as current in vault scope
- **OS citizenship is declarative where possible.** `Support/Info.plist` declares the
  `iriseditor` URL scheme and an `NSServices` entry; `AppDelegate` registers itself as
  `NSApp.servicesProvider` and `AppState.handleCaptureURL` routes
  `iriseditor://capture`, `iriseditor://open?path=…`, and `iriseditor://new?text=…`
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
- **HTML, PDF, and RTF export** reuse the preview's block and inline parsers through
  `MarkdownHTMLExport`, escaping text and raw HTML so exported files are safe to open in a
  browser and look consistent with the in-app preview. PDF and print jobs render that same
  HTML in an offscreen `WKWebView` (`MarkdownPDFExporter`), and the export stylesheet pins
  light, page-broken `@media print` rules.
- **Editing modes are pure where it counts.** `VimEngine` owns no AppKit state: it receives
  text and a selection and returns the next text, selection, and mode, so movements and
  operators are unit tested. `IrisTextView` applies the returned edit through
  `insertText(_:replacementRange:)` to keep Undo intact. Emacs bindings map Control/Option
  chords onto native `NSTextView` selectors with a small kill ring.
- **Plugins run in JavaScriptCore.** `PluginHost` scans the Application Support plugin
  folder, evaluates each plugin with only the `iris` registration API exposed, and bridges
  command contexts to `AppState`. Commands are namespaced by plugin id, appear in the
  Plugins menu and command palette, and can apply undoable edits, switch themes, or expose
  an HTML exporter. No filesystem or network APIs are exposed to scripts.

## Status

Iris Editor is a native Markdown editor and local-first vault reader. Editing, syntax
highlighting, preview, formatting, smart list continuation, HTML/PDF/RTF export,
printing, find/replace, go-to-line, tabbed Settings, animated tabs, the quick switcher,
command palette, the vault sidebar (files, outline, tags, backlinks, unlinked mentions,
local and vault graphs), wiki links, footnotes, transclusions, properties, daily notes,
templates, version history, Spotlight indexing, quick capture, Services and URL-scheme
handling, themes, Vim/Emacs keymaps, the JavaScript plugin API, and the status bar are
functional.

Deliberately not built: a plugin marketplace, Canvas, and mobile. See
[`research/positioning.md`](research/positioning.md) for the parity ledger and the
one-bet-per-round plan that this build follows.

Autocomplete is handled by the writing assistant instead of a bundled language model:
Apple Intelligence (Foundation Models) on-device, or a remote provider configured in
Settings ▸ AI. There is no separate local-model download or conversion step.

## License

No license file yet — all rights reserved by Apollo Studio Moonshot unless stated otherwise.
