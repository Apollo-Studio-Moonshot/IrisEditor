# Iris Editor Plugins

Iris Editor has a small, sandboxed JavaScript extension API built on **JavaScriptCore**.
Plugins can add commands, exporters, and theme-switching commands without changing the
app or linking a framework.

## Where plugins live

Plugins are loaded from:

```
~/Library/Application Support/IrisEditor/Plugins/
```

`Iris Editor ▸ Plugins ▸ Open Plugins Folder` reveals the directory. A plugin is either:

- a folder containing `plugin.json` and a JavaScript entry file (`main.js` by default), or
- a standalone `.js` file.

Reload after editing with `Iris Editor ▸ Plugins ▸ Reload Plugins`. Disable individual
plugins in **Settings ▸ Plugins**.

## Manifest

```json
{
  "id": "hello-iris",
  "name": "Hello Iris",
  "version": "1.0.0",
  "author": "Your Name",
  "summary": "Example commands and an exporter.",
  "main": "main.js"
}
```

Only `id` and `main` affect loading; the rest is shown in Settings. A missing manifest is
also fine when the folder contains `main.js` (the folder name becomes the id).

## Commands

```js
iris.registerCommand(
  { id: "word-count", title: "Word Count", shortcut: "command+option+w" },
  function (ctx) {
    var words = ctx.text.trim().split(/\s+/).filter(Boolean).length;
    ctx.alert("Word Count", words + " words");
  }
);
```

Shortcuts use the same syntax as Settings keybindings (`command+option+w`). A command
without a shortcut still appears in the **Plugins** menu and the command palette.

### `ctx`

| Property / method | Description |
|---|---|
| `ctx.text` | Current Markdown source |
| `ctx.selectionStart`, `ctx.selectionLength` | Selection in UTF-16 offsets |
| `ctx.documentName`, `ctx.filePath` | Document metadata |
| `ctx.insertText(value)` | Insert at the cursor (undoable) |
| `ctx.replaceSelection(value)` | Replace the selection |
| `ctx.setText(value)` | Replace the whole document |
| `ctx.setSelection(location, length)` | Move the selection |
| `ctx.save()` | Save the active document |
| `ctx.alert(title, message)` | Show a native alert |
| `ctx.setAccent("#7C6CF0")` | Set a custom accent color |
| `ctx.setPreviewTheme("midnight")` | `system`, `paper`, `sepia`, or `midnight` |
| `ctx.setAppearance("dark")` | `system`, `light`, `dark`, or `highContrast` |

Theme commands are just commands that call the setters above, for example:

```js
iris.registerCommand({ id: "night", title: "Theme: Night" }, function (ctx) {
  ctx.setAppearance("dark");
  ctx.setPreviewTheme("midnight");
  ctx.setAccent("#7C6CF0");
});
```

## Exporters

```js
iris.registerExporter(
  { id: "minimal-html", title: "Minimal HTML", extension: "html" },
  function (doc) {
    var escaped = doc.markdown
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
    return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>"
      + doc.title + "</title></head><body><pre>" + escaped + "</pre></body></html>";
  }
);
```

Exporters appear under **Plugins ▸ Export with Plugin** and return a complete HTML
document. `doc` contains `markdown`, `title`, and `theme` (the active preview theme id).

## `iris` helpers

| Helper | Description |
|---|---|
| `iris.registerCommand(meta, fn)` | Register a command |
| `iris.registerExporter(meta, fn)` | Register an HTML exporter |
| `iris.log(message)` | Write to the app's console log |
| `iris.id`, `iris.name` | This plugin's id and display name |

## Security

Plugins run in an in-process JavaScriptCore context. They receive **no filesystem,
network, or AppKit access**; the `iris` and `ctx` APIs above are the entire surface.
Only install plugins you trust, since JavaScript can still consume CPU while running.
