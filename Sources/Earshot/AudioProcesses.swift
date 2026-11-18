import AppKit
import CoreAudio

enum CoreAudioError: LocalizedError {
    case status(String, OSStatus)
    var errorDescription: String? {
        switch self {
        case let .status(what, code): return "\(what) failed (OSStatus \(code))"
        }
    }
}

@inline(__always)
func check(_ status: OSStatus, _ what: String) throws {
    if status != noErr { throw CoreAudioError.status(what, status) }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    func read<T>(_ selector: AudioObjectPropertySelector, default value: T) throws -> T {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var result = value
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &result), "Read property \(selector)")
        return result
    }

    func readString(_ selector: AudioObjectPropertySelector) throws -> String {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<CFString>.size)
        var result: Unmanaged<CFString>?
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &result), "Read string \(selector)")
        return (result?.takeRetainedValue() as String?) ?? ""
    }

    func readArray(_ selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size), "Size of \(selector)")
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &ids), "Read array \(selector)")
        return ids
    }
}

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

/// The "System Audio Recording Only" permission. macOS doesn't always show the prompt on its
/// own when a tap starts, so ask for it explicitly through TCC (the same call Apple's tools use).
enum AudioCapturePermission {
    enum Status { case granted, denied, unknown }

    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private static let service = "kTCCServiceAudioCapture" as CFString

    static func status() -> Status {
        guard let tcc, let sym = dlsym(tcc, "TCCAccessPreflight") else { return .unknown }
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        switch unsafeBitCast(sym, to: Preflight.self)(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request() async -> Bool {
        guard let tcc, let sym = dlsym(tcc, "TCCAccessRequest") else { return false }
        typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
        return await withCheckedContinuation { cont in
            unsafeBitCast(sym, to: Request.self)(service, nil) { cont.resume(returning: $0) }
        }
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
    }
}
