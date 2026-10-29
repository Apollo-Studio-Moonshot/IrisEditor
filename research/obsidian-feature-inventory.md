# Obsidian feature inventory (verified against official docs, app v1.14.5, 2026-10-22)

Source basis: `obsidian.md/help/*` (help.obsidian.md now 302-redirects there), docs repo `github.com/obsidianmd/obsidian-help` (en/ tree, 226 pages), `obsidian.md/pricing`, GitHub releases `obsidianmd/obsidian-releases`.
Legend: **[core]** = free, built in; **[paid]** = Sync / Publish / commercial license; **[plugin]** = community plugin only.

## 1. Editing core
- **Reading view** — rendered, non-editable view; default for non-editing reading. **[core]** (edit-and-read)
- **Editing view → Live Preview** — default WYSIWYG-ish mode; renders links/embeds/tables/math inline, reveals raw source on the cursor line. **[core]**
- **Editing view → Source mode** — raw Markdown everywhere, only syntax highlighting. **[core]**
- **Split panes** — drag a tab to any edge to split; tab groups are resizable and each group holds its own history. **[core]** (tabs)
- **Stacked tabs** — a tab group can be "stacked" (vertical card stack) instead of a horizontal strip. **[core]** (tabs#Stack tab groups)
- **Linked views** — panes can be linked so they follow the active note. **[core]** (tabs#Linked views)
- **Pop-out windows** — move a note or a whole tab into a separate OS window. **[core]** (pop-out-windows)
- **Command palette** — fuzzy command search, pinnable commands, hotkey assignment. **[core]**
- **Quick switcher** (`Cmd+O`) — fuzzy match on filename + aliases, Enter creates the note if missing. **[core]**
- **Outline** — heading tree of active note, click to jump. **[core]**
- **Backlinks pane** — two collapsible sections: *Linked mentions* and *Unlinked mentions* (plain-text occurrences, including alias occurrences). **[core]**
- **Outgoing links pane** — all links from the active note, incl. unresolved ones. **[core]**
- **Folding** — fold headings and indented lists; `Fold all headings and lists` / `Unfold all`. On by default, toggle in Settings → Editor. **[core]**
- **Block references** — `^blockid` at end of block, linked as `[[note#^blockid]]`; Obsidian-proprietary, links break in other Markdown apps. **[core]** (links)
- **Footnotes** — `[^1]` syntax plus a dedicated **Footnotes view** sidebar. **[core]** (syntax, plugins/footnotes)
- **Comments** — `%%inline%%` and multi-line `%% block %%`, hidden in Reading view; Obsidian-proprietary (use `<!-- -->` for portability). **[core]**
- **Tags pane** — flat list of every tag in the vault, supports nested `#a/b`. **[core]** (plugins/tags)
- **Properties (YAML frontmatter) UI** — typed key/value editor above the note; types: Text, List, Number, Checkbox, Date, Date & time, Tags; type is vault-global per property name. **Properties view** lists all vault properties. **[core]** (properties, plugins/properties)
- **Aliases** — `aliases:` frontmatter list; autocompletes in `[[`, inserts `[[Real Name|Alias]]` for portability, powers unlinked-mention matching. **[core]** (aliases)
- **Canvas** — infinite 2D board; cards from text, notes, media, web pages, bases, folders; `.canvas` saved in open **JSON Canvas** format. **[core]** (plugins/canvas)
- **Bookmarks** — save notes, headings, *searches*, and groups of files (successor of "Star"). **[core]** (plugins/bookmarks)
- **Workspaces** — save/load named layout layouts; tabs page also has "Save layouts". **[core]**
- **Slash commands** — `/` menu inside the editor. **[core]** (plugins/slash-commands)
- **Multiple cursors**, **Find & replace** (per-note and vault-wide). **[core]**
- **Not present natively**: true outliner/zoom (Logseq-style indent-everything), block-level attributes/classes — both only via community plugins.

## 2. Linking & knowledge features
- **Wikilinks `[[Note]]`** (default, compact) vs **Markdown links `[Note](Note.md)`** — global switch *Settings → Files and links → Use [[Wikilinks]]*; Markdown destinations must be URL-encoded. **[core]** (links)
- **Rename refactor** — renaming/moving a file updates all internal links automatically (configurable: auto-update or prompt). **[core]** (links)
- **Unresolved links** — a link to a nonexistent note renders distinctly and creates the file at the link's folder path on click. **[core]**
- **Heading anchors** — `[[#Heading]]`, `[[Note#Heading]]`, `[[Note#H1#H2]]`; vault-wide heading search `[[## term]]`. **[core]**
- **Block search** — `[[^^term]]` across the vault. **[core]**
- **Embeds / transclusion** — `![[Note]]`, `![[Note#Heading]]`, `![[Note#^blockid]]`, images with `|640x480` or `|100` (proportional). **[core]** (embeds)
- **Graph view** — global graph (filters, color groups, display, forces, time-lapse animation) and **local graph** per note. **[core]** (plugins/graph)
- **Note composer** — merge two notes / extract selection into a new note (with optional template). **[core]** (plugins/note-composer)
- **Page preview** — hover preview of links (enable plugin; `Cmd`+hover while editing). **[core]**
- **Format converter** — bulk-convert property value formats (e.g. text ↔ list ↔ tags). **[core]** (plugins/format-converter)
- **Bases** — database-style views (table / list / cards / kanban / map) over note properties, with formulas and functions; `.base` files or embedded code blocks. **[core]** (bases)
- **No automatic link creation**: plain-text mentions become links only by explicit action (unlinked mentions "Link" button) or a plugin.

## 3. Search
- **Vault search pane** — full text, sortable results, case sensitivity, copy results, result-count. **[core]** (plugins/search)
- **Operators**: `file:` `path:` `content:` `match-case:` `ignore-case:` `tag:` `line:` `block:` `section:` `task:` `task-todo:` `task-done:`; nesting with parentheses, `OR`, `-` negation, quoted phrases. **[core]**
- **Property queries**: `[property]`, `[property:value]`, `[property:null]`, with sub-queries (`[status:Draft OR Published]`). **[core]**
- **Regex search** — toggle in the search pane. **[core]**
- **Embedded query blocks** — save a search inside a note. **[core]**
- **Quick switcher fuzzy matching** — filenames + aliases only, not body text. **[core]**
- **Saved searches** — no dedicated feature; bookmarks can store a search. **[core]**
- **Omnisearch** (community) — better full-text ranking, PDF/OCR indexing, inline suggestions. **[plugin]**
- **Dataview / Bases** — query-layer search over properties and links. **[plugin]** / **[core]**

## 4. Markdown extensions (Obsidian Flavored Markdown)
- **GFM tables** — pipes optional, `:--`/`:-:`/`--:` alignment, Live Preview context menu to add/delete/sort columns and rows. **[core]** (advanced-syntax)
- **Task lists** — `- [ ]` / `- [x]`; no native due dates or reminders. **[core]**
- **Math** — LaTeX via **MathJax**, `$$...$$` block, `$...$` inline. **[core]**
- **Mermaid diagrams** — rendered by Obsidian's own renderer (Pele); flowcharts, sequence, timeline etc.; `internal-link` CSS class makes nodes linkable (those links do not appear in Graph view). **[core]**
- **Footnotes** — `[^1]` / `[^1]: text`. **[core]**
- **Callouts/admonitions** — `> [!note]`, custom titles, foldable (`[!note]-`), nested; types incl. note/tip/warning/danger/info/example/quote/success/failure/bug/question; custom types via CSS. **[core]** (callouts)
- **Code blocks** — syntax highlighting, inline code. **[core]**
- **HTML** — raw HTML allowed but constrained: no Markdown inside an HTML block, blocks must be self-contained; `<mark>`, `<u>`, `<span>`, comments. **[core]** (html)
- **Highlights** — `==highlight==`, plus highlight colors. **[core]**
- **CSV** — not rendered natively (plugin territory). **[plugin]**
- **PDF embed** — `![[file.pdf]]` inline; page-level behavior varies on small screens. **[core]** (embeds, file-formats)
- **Audio/video embed** — `.mp3 .m4a .ogg .wav .flac .webm .3gp`, `.mp4 .mov .mkv .ogv .webm`; codec support depends on device. **[core]**
- **Web/iframe embed** — YouTube and tweet embeds are special-cased; general iframes are unreliable, and the **Web viewer** core plugin opens external pages in an in-app browser instead (with Reader view, ad blocking, save-to-vault). **[core]** (embed-web-pages, plugins/web-viewer)
- **Frontmatter/properties** — YAML at top of file, typed via UI. **[core]**
- **Block-level attributes** — no `{.class}` / attribute syntax; only block IDs (`^id`). **[none]**

## 5. Organization
- **Folders** — real filesystem folders, drag & drop in File explorer. **[core]**
- **Tags** — inline `#tag`, nested `#a/b`, `tag:` search, Tags view; tag format restrictions apply. **[core]** (tags)
- **Properties** — typed metadata, vault-wide schema per property name. **[core]**
- **Daily notes** — per-day note from a template, date format configurable, integrates with date properties. **[core]** (plugins/daily-notes)
- **Templates** — core template folder + `{{date}}`, `{{title}}`, `{{time}}` variables (Templater community plugin for logic/JS). **[core]** (plugins/templates)
- **Unique note creator** — Zettelkasten-style timestamped note IDs, optional template. **[core]**
- **Random note** — resurfacing. **[core]**
- **Bookmarks** — notes/headings/searches/groups. **[core]**
- **File recovery** — automatic local snapshots; default at least 5 min apart, kept 7 days, stored in the global settings folder (not the vault), device-local (not synced), diff view + restore. **[core]** (plugins/file-recovery)
- **Local version history** — the above (free, per device); cross-device/1-month or 12-month history requires **Sync**. **[paid]**
- **Bases** — table/list/cards/kanban/map views, filters, formulas, functions. **[core]** (bases)

## 6. Export / interop
- **PDF export** — native export of a note. **[core]**
- **HTML / docx export** — not native; via **Pandoc plugin** or Publish. **[plugin]**
- **Web Clipper** — free official extension for Chrome/Brave/Arc/Orion, Firefox (+ mobile), Safari (macOS/iOS/iPadOS), Edge; templates, variables, filters, logic, highlighter, reader mode, AI "Interpreter". **[core]** (web-clipper)
- **Importer** — official community plugin: Notion, Evernote, Roam, Apple Notes, Apple Journal, Bear, Craft, Logseq, OneNote, Google Keep, Airtable, Tomboy/Gnote, HTML, Markdown, CSV, Textbundle; import templates. **[plugin]** (plugins/importer, import notes)
- **Obsidian URI** — `obsidian://open|new|daily|unique|search|choose-vault` for cross-app automation. **[core]** (uri)
- **Obsidian CLI** — full command-line control of the desktop app (requires installer 1.12.7+), incl. dev commands/screenshots. **[core]** (cli)
- **Obsidian Headless** — open beta, standalone Node 22+ client (`npm i -g obsidian-headless`) for Sync/Publish without the desktop app. **[core/beta]** (headless)
- **Publish** — hosted site at `publish.obsidian.md/<site>` or custom domain; permalinks, SEO, analytics, custom CSS/theme, collaboration, 50 MB per-file upload limit, minimal community-plugin support (raw-Markdown plugins only; Dataview-style blocks fail). **[paid]** (publish, publish/limitations)

## 7. Extensibility & platform
- **Plugin API** — TypeScript against the `obsidian` module; editor is **CodeMirror 6**; desktop runtime is **Electron** (Node.js available), mobile is a WebView with no Node/Electron APIs → `Platform` checks and `isDesktopOnly` flags. **[core]** (docs.obsidian.md mobile development)
- **Themes + CSS snippets** — Appearance settings, community theme browser, per-vault snippets, `publish.css` for Publish. **[core]**
- **Community plugin marketplace** — in-app Browse + `community.obsidian.md` directory; **Restricted Mode is on by default**; plugins inherit Obsidian's full privileges (file access, network, installing programs) with no per-permission sandbox. **[core]** (community-plugins, plugin-security)
- **Mobile apps** — iOS/iPadOS and Android, widgets, Siri/shortcuts, mobile toolbar, share-sheet capture; feature parity is close but plugin support is limited. **[core]** (mobile)
- **Sync** — paid, off-site remote vault, **AES-256 end-to-end encryption**, selective sync, shared vaults/collaboration, regional servers, Sync history sidebar. Plans: Standard 1 vault / 5 MB max file / 1 GB / 1-month history; Plus 10 vaults / 200 MB / 10–100 GB / 12-month history. $4/user/mo billed annually (entry price). **[paid]** (sync, sync/plans, sync/version-history)
- **Publish** — $8/site/mo billed annually. **[paid]**
- **Commercial license** — $50/user/yr, and per the pricing FAQ it is *not required* — it is an optional support license. **Catalyst** $25 one-time (early access builds, badges). **[paid, optional]**
- **Local REST API** — community plugin exposing an HTTP API to the vault. **[plugin]**
- **MCP / LLM access** — no official MCP server; community `obsidian-mcp-plugin` (HTTP transport, semantic vault ops) is the common route; Sync/Headless can also feed agentic tools. **[plugin]**

## 8. Performance & storage
- **Vault = plain folder** — notes are `.md` files plus `.base`, `.canvas`, images/audio/video/PDF; any external editor or file manager can change them and Obsidian reloads. **[core]** (data-storage, file-formats)
- **Config** — per-vault `.obsidian/` (hotkeys, themes, plugins, `workspace.json` layout); global settings in `~/Library/Application Support/obsidian` on macOS. **[core]**
- **No server database / no lock-in**, but there *is* a local **metadata cache** held in IndexedDB (powers Graph, Outline, search, backlinks), rebuilt on demand; Apple Lockdown Mode can prevent it persisting → reindex each launch. **[core]**
- **Attachments** — default location vault root, configurable to a subfolder or "same folder as current file"; paste/drag&drop copies in automatically. **[core]** (attachments)
- **Sync caveats** — iCloud Drive fine for macOS/iOS, but iCloud Drive on Windows can duplicate/corrupt; OneDrive/Google Drive community-reported hazards; Syncthing and Git are documented alternatives; official recommendation is Sync. **[core doc]** (sync-notes)
- **Memory/startup** — Electron app; first index of a large vault is the main cold-start cost.

## Top differentiators users cite vs a plain Markdown editor
1. **Backlinks + unlinked mentions** — reverse-link graph with plain-text detection, no manual bookkeeping.
2. **Graph view** — global/local visual network of the vault.
3. **Plugin ecosystem** — Dataview, Templater, Excalidraw, Kanban, Omnisearch, Local REST API; capability ceiling far above any built-in editor.
4. **Local plain-text files, no database, Git-able** — zero lock-in, cloud optional.
5. **Canvas** — infinite board on the open JSON Canvas format.
6. **Bases** — database-like table/kanban/cards/map views over frontmatter, now core.
7. **Live Preview + embeds + block references** — transclusion and block-level deep links inside the editor.
8. **Typed properties + operator-rich search** — `[prop:value]`, `task-todo:`, `section:`, regex.
9. **Free, no account, cross-platform** — macOS/Windows/Linux/iOS/Android, commercial use permitted without a license.
10. **Keyboard-centric navigation** — command palette, quick switcher, slash commands, workspace layouts, hotkeys.
11. **Automation surface** — Obsidian URI, CLI, Headless, Web Clipper.
12. **Deep theming** — themes + CSS snippets + `publish.css`.

## Gaps worth flagging when comparing to a native macOS editor
- No native outliner/zoom, no block-level attributes (`{.class}`), no native CSV rendering, no native DOCX/HTML export.
- Proprietary syntax (`%%comments%%`, `^blockid`) hurts portability.
- Electron memory footprint; large-vault cold indexing.
- Mobile plugins cannot use Node/Electron; some plugins are desktop-only.
- Publish has weak plugin support (50 MB file cap, no Dataview-style render blocks); iCloud-on-Windows and Lockdown Mode are documented footguns.

## Sources (official)
Views/modes [edit-and-read](https://obsidian.md/help/edit-and-read) · [tabs](https://obsidian.md/help/tabs) · [workspace](https://obsidian.md/help/workspace) · [pop-out-windows](https://obsidian.md/help/pop-out-windows) · [appearance](https://obsidian.md/help/appearance) · syntax [syntax](https://obsidian.md/help/syntax) · [advanced-syntax](https://obsidian.md/help/advanced-syntax) · [obsidian-flavored-markdown](https://obsidian.md/help/obsidian-flavored-markdown) · [callouts](https://obsidian.md/help/callouts) · [html](https://obsidian.md/help/html) · [folding](https://obsidian.md/help/folding) · links [links](https://obsidian.md/help/links) · [embeds](https://obsidian.md/help/embeds) · [aliases](https://obsidian.md/help/aliases) · [properties](https://obsidian.md/help/properties) · [tags](https://obsidian.md/help/tags) · [bases](https://obsidian.md/help/bases) · plugins [plugins](https://obsidian.md/help/plugins) · [plugins/search](https://obsidian.md/help/plugins/search) · [plugins/graph](https://obsidian.md/help/plugins/graph) · [plugins/canvas](https://obsidian.md/help/plugins/canvas) · [plugins/backlinks](https://obsidian.md/help/plugins/backlinks) · [plugins/outline](https://obsidian.md/help/plugins/outline) · [plugins/quick-switcher](https://obsidian.md/help/plugins/quick-switcher) · [plugins/command-palette](https://obsidian.md/help/plugins/command-palette) · [plugins/note-composer](https://obsidian.md/help/plugins/note-composer) · [plugins/file-recovery](https://obsidian.md/help/plugins/file-recovery) · [plugins/footnotes](https://obsidian.md/help/plugins/footnotes) · [plugins/format-converter](https://obsidian.md/help/plugins/format-converter) · [plugins/slash-commands](https://obsidian.md/help/plugins/slash-commands) · [plugins/web-viewer](https://obsidian.md/help/plugins/web-viewer) · [plugins/workspaces](https://obsidian.md/help/plugins/workspaces) · [plugins/bookmarks](https://obsidian.md/help/plugins/bookmarks) · [plugins/daily-notes](https://obsidian.md/help/plugins/daily-notes) · [plugins/templates](https://obsidian.md/help/plugins/templates) · [plugins/importer](https://obsidian.md/help/plugins/importer) · storage [data-storage](https://obsidian.md/help/data-storage) · [file-formats](https://obsidian.md/help/file-formats) · [attachments](https://obsidian.md/help/attachments) · [sync-notes](https://obsidian.md/help/sync-notes) · sync [sync](https://obsidian.md/help/sync) · [sync/plans](https://obsidian.md/help/sync/plans) · [sync/version-history](https://obsidian.md/help/sync/version-history) · publish [publish](https://obsidian.md/help/publish) · [publish/limitations](https://obsidian.md/help/publish/limitations) · [web-clipper](https://obsidian.md/help/web-clipper) · [community-plugins](https://obsidian.md/help/community-plugins) · [plugin-security](https://obsidian.md/help/plugin-security) · [uri](https://obsidian.md/help/uri) · [cli](https://obsidian.md/help/cli) · [headless](https://obsidian.md/help/headless) · [mobile](https://obsidian.md/help/mobile) · [developers](https://obsidian.md/help/developers) · pricing [obsidian.md/pricing](https://obsidian.md/pricing) · [Mobile development (docs)](https://docs.obsidian.md/Plugins/Getting+started/Mobile+development) · [obsidian-mcp-plugin](https://github.com/aaronsb/obsidian-mcp-plugin) · [JSON Canvas](https://jsoncanvas.org/) · releases [obsidian-releases](https://github.com/obsidianmd/obsidian-releases/releases)
