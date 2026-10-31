# Iris Editor — parity ledger and differentiation bets

Written 2026-10-31, against `research/obsidian-feature-inventory.md` (Obsidian 1.14.5)
and the current source tree (`Sources/IrisEditor/`, ~18.5k lines).

Purpose: decide where Iris *must* feel like Obsidian (table stakes users will notice
immediately), and where it should deliberately diverge so it is not a clone.

---

## 1. The three layers where Iris should be similar

"Similar to Obsidian" is really three separate contracts. Break one and the app stops
feeling familiar; break neither and there is no product.

**A. Data contract — plain Markdown in a plain folder.**
No database, no proprietary store, Git-able, editable by any other tool.
Iris already honours this: `VaultScanner` reads `.md` from a folder, notes are ordinary
files, no `.obsidian` config dir is written into the user's tree.

**B. Navigation contract — keyboard-first retrieval.**
`⌘P` quick switcher, command palette, outline, backlinks, tags pane.
If a user cannot get to a note in two keystrokes, it is not an Obsidian-like app.
Iris has all five.

**C. Syntax contract — Obsidian Flavored Markdown.**
`[[wikilinks]]`, `==highlight==`, callouts, `%%comments%%`, `^blockid`, frontmatter.
A note written in Obsidian must open in Iris without looking broken.
Iris covers wikilinks, highlights, callouts, tables, math (LaTeX), Mermaid, frontmatter.

## 2. Parity ledger

Legend: **done** = shipped and usable · **partial** = works but weaker than Obsidian ·
**gap** = absent.

| Capability | Status | Notes |
|---|---|---|
| Folder vault + file tree | done | `Models/Vault.swift`, files pane |
| Quick switcher / command palette | done | `⌘P`, `⇧⌘P`, `FuzzyMatch` |
| Outline | done | ATX + Setext |
| Backlinks | done | linked + **unlinked mentions** (`VaultScanner.unlinkedMentions`) |
| Graph | done | local depth-1 **and whole-vault** scope (`graph(around: nil)`, 60-node cap) |
| Tags pane | done | nested `#a/b` |
| Properties / frontmatter UI | partial | card editor; no typed properties, no vault-wide schema view |
| Vault search | partial | operators `tag: path: file: match-case: -`; no regex, `task:`, `section:`, `block:`, property queries |
| Daily notes / templates | done | `DailyNotes`, template folder |
| Version history | done | `VersionHistoryStore` + `VersionHistoryView` — ahead of Obsidian's per-device file recovery |
| Wiki links, aliases, unresolved | done | `openWikiLink`, create-on-click |
| Rename refactor (update links) | partial | `renameCurrentFile` — verify whether inbound links are rewritten |
| Callouts, tables, math, Mermaid | done | `MarkdownBlocks`, `LaTeXMathRenderer`, `MermaidRenderer` |
| Footnotes | done | `MarkdownFootnoteIndex`, preview list, HTML export section |
| Embeds / transclusion | done | `Transclusion.swift`; note, `#Heading`, `#^block`, images, 2-level nesting |
| Block references | partial | `#^id` embeds a block; no `((id))` inline refs |
| Folding headings/lists | gap | no `NSLayoutManager` folding |
| Multiple cursors | gap | no `selectAllOccurrences`-style support |
| Slash commands | gap | no `/` menu in editor |
| Split panes | partial | `openInSecondPane` exists; no drag-to-split, no linked views |
| Pop-out windows | gap | single window |
| Workspaces / layouts | partial | `SessionStore` restores session only |
| Bookmarks | gap | none |
| Canvas | gap | none |
| Bases (database views) | gap | properties exist, no table/kanban views over them |
| Plugin ecosystem | partial | `PluginHost` (JavaScriptCore): commands, exporters, theme switch |
| Themes / CSS snippets | partial | built-in themes only, no user CSS |
| Sync / real-time collab | gap | none |
| Mobile | gap | macOS only, by design |
| CLI / URI | partial | `capture`, `open?path=`, `new?text=`, NSServices; no CLI |
| Importer / web clipper | gap | none |
| Publish | gap | HTML/PDF/RTF export only |

**Reading the table:** the gaps that hurt most were *footnotes, embeds, global graph,
unlinked mentions* — all four shipped in this round. What remains in that tier is
*folding* and *multi-cursor*, both editor-level polish rather than vault features. Everything below that line is breadth, not depth, and
breadth is the one race Iris cannot win against a plugin ecosystem.

## 3. What Obsidian structurally cannot copy

These are not features; they are properties of the substrate. They are where "unique"
actually lives.

1. **Native text system.** `NSTextView`/TextKit and AppKit inside a real document app.
   Obsidian's editor is CodeMirror 6 in Electron — no native text services, no
   per-range typographic control, and VoiceOver reaches it through Chromium's a11y layer
   rather than AppKit directly.
2. **OS citizenship.** Spotlight indexing (`SpotlightIndexer`), Quick Look, Services menu,
   document types in `Info.plist`, Shortcuts, `MenuBarExtra` capture. A web app in a
   bundle cannot be the system's Markdown layer.
3. **Document identity.** `NSDocument`-style semantics — autosave, versions, iCloud,
   "open recent", unsaved-draft recovery (`DraftStore`), proxy icons.
4. **Resource profile.** Sub-second cold start, triple-digit MB, fanless laptops stay
   fanless. Measurable and defensible in one benchmark table.
5. **Vault-free operation.** Any folder, or a single loose `.md` file. Obsidian's vault
   model forces a container and a config directory.
6. **Capability-safe extensibility.** `PluginHost` runs plugin JS in JavaScriptCore with
   only `iris.registerCommand` / `iris.registerExporter` exposed — no filesystem, no
   network. Obsidian's own docs state community plugins inherit full privileges with no
   per-permission sandbox. That difference is a *security* argument, not a feature
   argument, and it sells to schools, studios, and anyone who reads release notes.
7. **Apple-platform AI.** Foundation Models, on-device, no API key, no note text leaving
   the machine.

## 4. Differentiation bets, ranked by moat-per-effort

**1. Editable transclusion (the signature feature).**
Obsidian renders `![[Note#Heading]]` as a *read-only* embed. In TextKit you can nest live
text storage: the embedded section is editable in place, edits write back to the source
note. Position it as *"notes that compose like functions."* This is the one feature that
is both obviously Obsidian-adjacent and impossible for Obsidian to ship without rewriting
its editor. High effort, highest moat.

**2. Typed links and semantic graph.**
Give entities types via frontmatter (`type: person`, `type: meeting`), so `[[Ada]]` is an
edge with a label. Then the graph answers questions Obsidian's cannot:
"meetings mentioning people I have not linked to in 90 days", "orphan notes that mention
this project". Obsidian's graph is untyped and its query layer (Dataview/Bases) does not
produce graph traversal. Local graph already exists — extend the model, not the viewport.

**3. Time as a first-class axis.**
`VersionHistoryStore` already beats Obsidian's local recovery. Promote it: a scrubbable
timeline per note, "what did this note look like the day I started it", per-vault diffs of
a thought over months. Knowledge tools store text; almost none store *change*.

**4. Iris as the OS Markdown layer.**
Finish the loop: Quick Look generator for `.md`, `NSServices` entry ("Capture to Iris"),
App Intents so Shortcuts/Siri can search the vault, Spotlight deep links that open the
exact heading, `MenuBarExtra` capture (exists), `iriseditor://` beyond capture.
Every one of these is a capability Obsidian can never hold.

**5. Safe plugin model with a permissions UI.**
Add a manifest permission list (`vault.read`, `vault.write`, `net.http`, `ui.notice`),
show it before enabling, and log what a plugin touched. Turn the sandbox from a
limitation into the headline. Then grow the API deliberately (editor decorations,
status bar items, settings panes) rather than chasing Obsidian's surface area.

**6. Write-time intelligence, not just storage.**
Iris measures nothing about *writing*. Session streaks, per-note time-on-page, "resume
the thought" (cursor + last sentence + the note you linked just before), a daily review
queue of notes touched 3/7/30 days ago, and link-health (dangling, unlinked mentions).
Obsidian's plugin ecosystem approximates bits of this; nobody ships it native and calm.

**7. Collaboration that is actually free.**
Obsidian charges for Sync (~$4/user/mo) and has no real-time co-editing. CloudKit
private-DB sync plus a small relay for live cursors is a large build but a genuine
category difference — and it fits the "your files, your iCloud" story.

**8. Export that is a product, not a menu item.**
HTML/PDF/RTF already share one parser (`MarkdownHTMLExport`). Add DOCX, ePub, and a
static-site export with themes and backlink pages — "write here, publish anywhere", which
is exactly the slot Obsidian fills with a paid Publish add-on.

**Skip:** cloning Canvas, cloning Bases, cloning the plugin marketplace, mobile. Each is a
multi-year breadth race where Iris starts at zero plugins and ends as a worse Obsidian.

## 5. Suggested sequencing

- **Shipped this round:** footnotes (parse + preview + HTML export), editable transclusion
  (`![[…]]` whole note / `#Heading` / `#^block`, images, 2-level nesting cap), unlinked
  mentions in the backlinks pane, local/vault graph toggle, `iriseditor://open?path=`,
  `iriseditor://new?text=`, `NSServices` "Open Markdown in Iris", README rewrite.
- **Still open from the old "now" list:** heading/list folding, multi-cursor, slug and
  markdown-lint on save, Quick Look extension, App Intents, inline `((block))` refs.
- **Next (deepen the signature bet):** edit-inside-transclusion (write-through to the
  source note), embed-in-editor previews, and a "linked vs. mentioned" badge in the
  status bar.
- **Then (the OS story beyond Services):** Quick Look, App Intents, Spotlight *actions*
  (not just results), Shortcuts app actions.
- **Later (compounding):** typed links, time axis, permissions UI, sync.

## 6. One-line positioning

> Obsidian is a vault you install. Iris is the Markdown layer of your Mac: native text,
> Spotlight and Quick Look, safe plugins, and notes that compose.
