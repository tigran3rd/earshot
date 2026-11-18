import AppKit

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
