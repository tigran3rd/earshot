import CoreAudio
import Foundation

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

    func read<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, default value: T) throws -> T {
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
