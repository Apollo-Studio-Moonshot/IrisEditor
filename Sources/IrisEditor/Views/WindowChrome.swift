import AppKit
import SwiftUI

/// The window's content sits on the real desktop material instead of a painted gradient.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Applies native macOS document chrome: a real title bar, unified toolbar, proxy icon,
/// edited dot, and a translucent window that can show the desktop material behind it.
struct WindowConfigurator: NSViewRepresentable {
    let displayName: String
    let fileURL: URL?
    let isDirty: Bool

    func makeNSView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        view.onWindow = configure
        return view
    }

    func updateNSView(_ nsView: WindowObservingView, context: Context) {
        nsView.onWindow = configure
        if let window = nsView.window {
            configure(window)
        }
    }

    private func configure(_ window: NSWindow) {
        window.title = displayName
        window.representedURL = fileURL
        window.isDocumentEdited = isDirty
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        if window.frameAutosaveName.isEmpty {
            window.setFrameAutosaveName("IrisEditorMainWindow")
        }
    }
}

final class WindowObservingView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindow?(window)
        }
    }
}

/// A pure Liquid Glass surface used behind the editor's text area.
struct GlassBackdrop: NSViewRepresentable {
    var style: NSGlassEffectView.Style = .regular
    var cornerRadius: CGFloat = 14
    var interactive: Bool = false

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = style
        glass.cornerRadius = cornerRadius
        if #available(macOS 27.0, *) {
            // Golden Gate: interactive glass responds to pointer interaction.
            glass.effectIsInteractive = interactive
        }
        return glass
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.style = style
        nsView.cornerRadius = cornerRadius
        if #available(macOS 27.0, *) {
            nsView.effectIsInteractive = interactive
        }
    }
}
