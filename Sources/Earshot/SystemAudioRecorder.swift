import AVFoundation
import CoreAudio
import Observation
import os

private let log = Logger(subsystem: "com.tigrank.earshot", category: "capture")

/// What to record: one app, or every app's audio mixed together. Never the microphone.
enum CaptureSource: Hashable {
    case allApps
    case app(AppSource)

    var label: String {
        switch self {
        case .allApps: return "All Apps"
        case .app(let a): return a.name
        }
    }
}

/// Records what apps are playing using a Core Audio process tap. The tap doesn't mute
/// anything: you keep hearing the audio normally. Needs the "System Audio Recording Only"
/// permission (see AudioCapturePermission).
@MainActor @Observable
final class SystemAudioRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// RMS level (linear, 0...1) of the last ~50 ms of audio, for the VU meter.
    private(set) var level: Float = 0
    /// True once real (non-silent) audio has arrived during this recording.
    private(set) var heardSound = false
    /// Set by stop() if any audio couldn't be written to the file.
    private(set) var writeError: Error?

    private var session: TapSession?
    private var timer: Timer?
    private var startDate: Date?

    func start(source: CaptureSource, to url: URL) throws {
        guard !isRecording else { return }
        let session = TapSession(source: source, url: url)
        session.onLevel = { [weak self] rms in
            Task { @MainActor in
                guard let self else { return }
                self.level = rms
                if rms > 0.0005 { self.heardSound = true }
            }
        }
        try session.start()
        self.session = session
        isRecording = true
        heardSound = false
        writeError = nil
        elapsed = 0
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    /// Stops, finalises the file and returns its duration in seconds.
    @discardableResult
    func stop() -> TimeInterval {
        timer?.invalidate()
        timer = nil
        let duration = session?.stop() ?? 0
        writeError = session?.writeError
        session = nil
        isRecording = false
        level = 0
        elapsed = 0 // back to 0:00:00, so the counter never looks like it is still running
        return duration
    }
}

/// Owns the Core Audio objects for one recording. Not main-actor bound: the IO block runs
/// on its own queue and hands buffers to a serial writer queue so encoding never blocks IO.
///
/// When a process joins or leaves an app tap (say the browser starts a new audio helper),
/// Core Audio reconfigures the capture device and the IO callback can stop for good. A
/// watchdog notices the stall and rebuilds the device, and any gap is filled with silence
/// so the file always runs in real time.
private final class TapSession: @unchecked Sendable {
    let source: CaptureSource
    let url: URL
    var onLevel: (@Sendable (Float) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var tapUUID = UUID()
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var format: AVAudioFormat?

    // IO-queue state.
    private var firstHostTime: UInt64 = 0
    private var queuedFrames: Int64 = 0
    private var sumSquares: Double = 0
    private var sampleCount = 0

    private let lock = NSLock()
    private var lastCallback: UInt64 = 0
    private var framesWritten: AVAudioFramePosition = 0
    /// The first write failure, if any (writer-queue state; read after stop()).
    private(set) var writeError: Error?

    private let ioQueue = DispatchQueue(label: "earshot.tap.io", qos: .userInitiated)
    private let writeQueue = DispatchQueue(label: "earshot.tap.write", qos: .utility)
    private let controlQueue = DispatchQueue(label: "earshot.tap.control")
    private var watchdog: DispatchSourceTimer?

    init(source: CaptureSource, url: URL) {
        self.source = source
        self.url = url
    }

    func start() throws {
        do {
            try createTap()
            try createFile()
            try startDevice()
        } catch {
            tearDown()
            throw error
        }
        startWatchdog()
    }

    func stop() -> TimeInterval {
        controlQueue.sync {
            watchdog?.cancel()
            watchdog = nil
        }
        tearDown()
        // Pad silence up to the moment Stop was pressed.
        ioQueue.sync { padSilence(until: mach_absolute_time()) }
        var seconds: TimeInterval = 0
        writeQueue.sync {
            if let format { seconds = Double(framesWritten) / format.sampleRate }
            file = nil // closes and finalises the file
        }
        return seconds
    }

    // MARK: Setup

    private func createTap() throws {
        let desc: CATapDescription
        switch source {
        case .allApps:
            desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        case .app(let app):
            // Tap by bundle ID (macOS 26), so helper processes that start playing after we
            // begin (a new browser tab, say) are picked up too.
            desc = CATapDescription(stereoMixdownOfProcesses: [])
            desc.bundleIDs = app.tappedBundleIDs
            desc.isProcessRestoreEnabled = true
        }
        tapUUID = UUID()
        desc.uuid = tapUUID
        desc.name = "Earshot"
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        try check(AudioHardwareCreateProcessTap(desc, &tapID), "Creating the audio tap")

        var asbd = try tapID.read(kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw CoreAudioError.status("Reading the tap format", -1)
        }
        self.format = format
    }

    private func createFile() throws {
        guard let format else { return }
        let settings: [String: Any] = [ // AAC in .m4a, ~1 MB per minute
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: min(format.channelCount, 2),
            AVEncoderBitRateKey: 128_000,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
    }

    /// A private aggregate device containing the tap, with our IO callback running on it.
    private func startDevice() throws {
        let outputDevice = try AudioObjectID.system.read(kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                         default: AudioObjectID(kAudioObjectUnknown))
        let outputUID = try outputDevice.readString(kAudioDevicePropertyDeviceUID)
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Earshot Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
                  "Creating the capture device")
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) { [weak self] _, input, inputTime, _, _ in
            self?.handle(input, at: inputTime.pointee)
        }, "Creating the IO callback")
        lock.withLock { lastCallback = mach_absolute_time() }
        try check(AudioDeviceStart(aggregateID, procID), "Starting capture")
    }

    private func stopDevice() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
    }

    private func tearDown() {
        stopDevice()
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        // Let any buffer the IO queue already dispatched reach the writer.
        ioQueue.sync {}
    }

    // MARK: Watchdog

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let last = self.lock.withLock { self.lastCallback }
            guard hostSeconds(from: last, to: mach_absolute_time()) > 0.5 else { return }
            // The device stopped calling us. Rebuild it around the same tap.
            self.stopDevice()
            do { try self.startDevice() } catch { log.error("Restarting capture failed: \(error.localizedDescription, privacy: .public)") }
        }
        timer.resume()
        watchdog = timer
    }

    // MARK: IO

    private func handle(_ input: UnsafePointer<AudioBufferList>, at time: AudioTimeStamp) {
        let now = mach_absolute_time()
        lock.withLock { lastCallback = now }
        guard let format,
              let view = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil),
              view.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: view.frameLength)
        else { return }

        let host = time.mFlags.contains(.hostTimeValid) ? time.mHostTime : now
        if firstHostTime == 0 { firstHostTime = host }
        padSilence(until: host)

        // Copy out of Core Audio's memory before leaving the callback.
        copy.frameLength = view.frameLength
        let src = UnsafeMutableAudioBufferListPointer(view.mutableAudioBufferList)
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (s, d) in zip(src, dst) {
            guard let sp = s.mData, let dp = d.mData else { continue }
            let bytes = min(Int(s.mDataByteSize), Int(d.mDataByteSize))
            memcpy(dp, sp, bytes)
            let samples = sp.assumingMemoryBound(to: Float.self)
            for i in 0..<(bytes / 4) { sumSquares += Double(samples[i] * samples[i]) }
            sampleCount += bytes / 4
        }
        // Report the level about 20 times a second.
        if sampleCount >= Int(format.sampleRate * Double(format.channelCount)) / 20 {
            onLevel?(Float((sumSquares / Double(sampleCount)).squareRoot()))
            sumSquares = 0
            sampleCount = 0
        }
        queuedFrames += Int64(copy.frameLength)
        write(copy)
    }

    /// If the stream fell behind real time (callbacks stalled), write silence to catch up.
    private func padSilence(until host: UInt64) {
        guard let format, firstHostTime != 0 else { return }
        let expected = Int64(hostSeconds(from: firstHostTime, to: host) * format.sampleRate)
        var gap = expected - queuedFrames
        guard gap > Int64(format.sampleRate / 10) else { return }
        if gap > 0 { onLevel?(0) }
        while gap > 0 {
            let n = AVAudioFrameCount(min(gap, Int64(format.sampleRate)))
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n) else { return }
            silence.frameLength = n
            for b in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
                if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) }
            }
            write(silence)
            queuedFrames += Int64(n)
            gap -= Int64(n)
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        writeQueue.async { [weak self] in
            guard let self, let file = self.file else { return }
            do {
                try file.write(from: buffer)
                self.framesWritten += AVAudioFramePosition(buffer.frameLength)
            } catch {
                log.error("Writing audio failed: \(error.localizedDescription, privacy: .public)")
                if self.writeError == nil { self.writeError = error }
            }
        }
    }
}

private func hostSeconds(from a: UInt64, to b: UInt64) -> Double {
    guard b > a else { return 0 }
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return Double(b - a) * Double(info.numer) / Double(info.denom) / 1_000_000_000
}
