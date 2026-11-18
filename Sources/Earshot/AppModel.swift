import AppKit
import Observation

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let recorder = SystemAudioRecorder()

    var source: CaptureSource = .allApps {
        didSet {
            if case .app(let a) = source { UserDefaults.standard.set(a.bundleID, forKey: "sourceBundleID") }
            else { UserDefaults.standard.removeObject(forKey: "sourceBundleID") }
        }
    }
    /// Name for the next recording's file.
    var recordingName: String {
        didSet { UserDefaults.standard.set(recordingName, forKey: "recordingName") }
    }
    private(set) var lastRecording: URL?

    /// Recordings are saved here as .m4a files.
    let folder: URL = {
        let url = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earshot", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private var currentURL: URL?

    private init() {
        recordingName = UserDefaults.standard.string(forKey: "recordingName") ?? "My Recording"
        if let id = UserDefaults.standard.string(forKey: "sourceBundleID"), let app = AudioProcesses.app(bundleID: id) {
            source = .app(app)
        }
        // Ask for the System Audio Recording permission up front, so the first recording works.
        if AudioCapturePermission.status() != .granted {
            Task { _ = await AudioCapturePermission.request() }
        }
    }

    func toggleRecording() {
        recorder.isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        switch AudioCapturePermission.status() {
        case .granted: break
        case .denied:
            return alert("Earshot isn't allowed to record app audio",
                         "Turn on Earshot under System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only.",
                         openSettings: true)
        case .unknown:
            Task {
                if await AudioCapturePermission.request() {
                    startRecording()
                } else {
                    alert("Earshot needs permission to record app audio",
                          "Allow Earshot under System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only, then press Record again.",
                          openSettings: true)
                }
            }
            return
        }
        let url = nextFileURL()
        do {
            try recorder.start(source: source, to: url)
            currentURL = url
        } catch {
            alert("Couldn't start recording", error.localizedDescription)
        }
    }

    func stopRecording() {
        guard let url = currentURL else { return }
        let heard = recorder.heardSound
        recorder.stop()
        currentURL = nil
        lastRecording = url
        if let error = recorder.writeError {
            alert("Part of the recording couldn't be saved",
                  "\(url.lastPathComponent) may be incomplete. \(error.localizedDescription)")
        } else if !heard {
            alert("That recording is silent",
                  "Nothing played from \(source.label) while recording. If something did play, check that Earshot is allowed under System Audio Recording Only.",
                  openSettings: true)
        }
    }

    func revealLastRecording() {
        if let lastRecording, FileManager.default.fileExists(atPath: lastRecording.path) {
            NSWorkspace.shared.activateFileViewerSelecting([lastRecording])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }

    /// "My Recording.m4a", then "My Recording 2.m4a", and so on.
    private func nextFileURL() -> URL {
        let cleaned = recordingName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Recording" : cleaned
        var url = folder.appendingPathComponent(base + ".m4a")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n).m4a")
            n += 1
        }
        return url
    }

    private func alert(_ title: String, _ message: String, openSettings: Bool = false) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        if openSettings { a.addButton(withTitle: "Open Settings") }
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertSecondButtonReturn { AudioCapturePermission.openSettings() }
    }
}
