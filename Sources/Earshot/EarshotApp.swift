import SwiftUI

@main
struct EarshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        // The recorder panel is an AppKit window (see PanelWindow); SwiftUI only provides the
        // menu bar icon and the app's menus.
        MenuBarExtra {
            MenuBarContent().environment(model)
        } label: {
            if model.recorder.isRecording {
                Label(clock(model.recorder.elapsed), systemImage: "record.circle.fill")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(nsImage: MenuBarGlyph.image)
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(model.recorder.isRecording ? "Stop Recording" : "Start Recording") {
                    model.toggleRecording()
                }
                .keyboardShortcut("r")
                Button("Show Last Recording in Finder") { model.revealLastRecording() }
                Button("Open Recordings Folder") { NSWorkspace.shared.open(model.folder) }
            }
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(model.recorder.isRecording ? "Stop Recording (\(clock(model.recorder.elapsed)))"
                                          : "Start Recording") {
            model.toggleRecording()
        }
        Text("Source: \(model.source.label)")
        Divider()
        Button("Show Earshot") { AppDelegate.showPanel() }
        Button("Open Recordings Folder") { NSWorkspace.shared.open(model.folder) }
        Divider()
        Button("Quit Earshot") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

func clock(_ t: Double) -> String {
    let s = Int(max(0, t))
    return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var panel: PanelWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Self.showPanel()
    }

    /// Clicking the Dock icon brings the panel back, even after it was closed with ⌘W.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.showPanel()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let panel = Self.panel, panel.isVisible { panel.makeKeyAndOrderFront(nil) }
    }

    @MainActor static func showPanel() {
        if panel == nil { panel = PanelWindow() }
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
    }
}

/// A borderless window for the panel, so the wood frame and its rounded corners are the whole
/// window. Borderless windows normally can't take keyboard focus (so the name field couldn't be
/// typed in); this one can.
final class PanelWindow: NSWindow {
    @MainActor init() {
        let host = NSHostingView(rootView: RecorderPanel().environment(AppModel.shared))
        host.sizingOptions = [.intrinsicContentSize]
        let size = host.fittingSize
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                   backing: .buffered, defer: false)
        contentView = host
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        title = "Earshot"
        collectionBehavior = [.managed, .participatesInCycle]
        if !setFrameUsingName("EarshotPanel") { center() }
        setFrameAutosaveName("EarshotPanel")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Borderless windows have no close button, so ⌘W would just beep.
    override func performClose(_ sender: Any?) { close() }
    override func performMiniaturize(_ sender: Any?) { miniaturize(sender) }
}
