import AppKit
import CoreAudio

/// An app you can record from.
struct AppSource: Hashable, Identifiable {
    let bundleID: String
    let name: String
    let url: URL?
    var id: String { bundleID }

    var icon: NSImage {
        if let url { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    /// Bundle IDs whose audio belongs to this app. Browsers and Electron apps play sound from
    /// helper processes, which have their own bundle IDs inside the app bundle.
    var tappedBundleIDs: [String] {
        var ids: Set<String> = [bundleID]
        if bundleID == "com.apple.Safari" || bundleID.hasPrefix("com.apple.SafariTechnologyPreview") {
            ids.formUnion(["com.apple.WebKit.GPU", "com.apple.WebKit.WebContent"])
        }
        if let url { ids.formUnion(Self.helperBundleIDs(in: url)) }
        // Plus anything Core Audio already sees playing under this app's prefix.
        for p in AudioProcesses.bundleIDsWithAudio() where p.hasPrefix(bundleID) { ids.insert(p) }
        return ids.sorted()
    }

    private static func helperBundleIDs(in app: URL) -> [String] {
        let fm = FileManager.default
        let frameworks = app.appendingPathComponent("Contents/Frameworks")
        guard let e = fm.enumerator(at: frameworks, includingPropertiesForKeys: nil,
                                    options: [.skipsHiddenFiles]) else { return [] }
        var ids: [String] = []
        for case let url as URL in e {
            if url.pathExtension == "app" {
                if let id = Bundle(url: url)?.bundleIdentifier { ids.append(id) }
                e.skipDescendants()
            } else if url.pathComponents.count - frameworks.pathComponents.count > 6 {
                e.skipDescendants()
            }
        }
        return ids
    }
}

enum AudioProcesses {
    /// Bundle IDs of processes that have an audio connection right now.
    static func bundleIDsWithAudio(playingOnly: Bool = false) -> Set<String> {
        guard let ids = try? AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList) else { return [] }
        var out: Set<String> = []
        for id in ids {
            if playingOnly, ((try? id.read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0) == 0 { continue }
            if let b = try? id.readString(kAudioProcessPropertyBundleID), !b.isEmpty { out.insert(b) }
        }
        return out
    }

    /// Regular (Dock) apps that are running, with the ones playing sound first.
    static func runningApps() -> (playing: [AppSource], other: [AppSource]) {
        let me = Bundle.main.bundleIdentifier
        let playing = bundleIDsWithAudio(playingOnly: true)
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != me }
            .map { AppSource(bundleID: $0.bundleIdentifier!, name: $0.localizedName ?? $0.bundleIdentifier!,
                             url: $0.bundleURL) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        func isPlaying(_ a: AppSource) -> Bool {
            playing.contains { $0 == a.bundleID || $0.hasPrefix(a.bundleID + ".") }
                || (a.bundleID == "com.apple.Safari" && playing.contains("com.apple.WebKit.GPU"))
        }
        return (apps.filter(isPlaying), apps.filter { !isPlaying($0) })
    }

    static func app(bundleID: String) -> AppSource? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return AppSource(bundleID: bundleID, name: name, url: url)
    }
}
