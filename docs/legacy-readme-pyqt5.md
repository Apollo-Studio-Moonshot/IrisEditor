# Archived: Iris Editor (Python / PyQt5 prototype)

> **Archived — not the current codebase.** This documents the original Python prototype,
> which has since been rewritten as a native SwiftUI macOS app. No `main.py` remains in this
> repository. Kept for reference on intended feature set and the original GPT-2 autocomplete
> approach.

# Iris Editor - Plain Text Editor (PyQt5)

A lightweight **.txt file editor** with **line numbers**, basic editing features, and optional **GPT‑2 autocomplete**.

## ✅ Features
- Plain text editing (`.txt`)
- Line numbers (fixed-width font)
- Word count + file size shown in status bar
- Undo/redo, cut/copy/paste, select all
- File operations: New, Open, Save, Save As
- Settings (Ctrl+,) to change font family, font size, highlight line, tab width
- Find/Replace (Ctrl+F)
- Go-to-line (Ctrl+G)
- GPT-2 autocomplete support (Ctrl+Space)

## ⌨️ Keyboard Shortcuts
- **Ctrl+N**: New file
- **Ctrl+O**: Open file
- **Ctrl+S**: Save file
- **Ctrl+Shift+S**: Save file as
- **Ctrl+Q**: Close window
- **Ctrl+Z**: Undo
- **Ctrl+Y**: Redo
- **Ctrl+X**: Cut
- **Ctrl+C**: Copy
- **Ctrl+V**: Paste
- **Ctrl+A**: Select all
- **Ctrl+,**: Settings
- **Ctrl+F**: Find/Replace
- **Ctrl+G**: Go to line
- **Ctrl+Space**: Trigger GPT-2 autocomplete

## 🛠️ Requirements
- Python 3.8+
- `PyQt5` (install via `pip install PyQt5`)

### Optional (for GPT-2 autocomplete)
- `transformers` and `torch` (install via `pip install transformers torch`)
- A pretrained GPT-2 model directory (local)

## ▶️ Running
```sh
python3 main.py
```
> **Note:** Qt font warnings are suppressed during startup for cleaner output.

## 📦 Building a macOS App
To create a standalone macOS application (.app bundle):

1. Install PyInstaller:
   ```sh
   pip install pyinstaller
   ```

2. Build the app:
   ```sh
   pyinstaller --onedir --windowed --name IrisEditor main.py
   ```

3. The `TextEdit.app` will be created in the `dist/` directory. You can move it to your Applications folder or run it directly.
## 🚀 Using GPT-2 Autocomplete
1. Use **Model → Load GPT-2 Model…** to point to a local model directory.
2. Type some code or text and wait a moment — suggestions will appear automatically.
3. Press **Tab** to accept the suggestion, or **Esc** to dismiss it.

> Tip: You can use a standard Hugging Face GPT-2 model folder or your own pretrained checkpoint.
