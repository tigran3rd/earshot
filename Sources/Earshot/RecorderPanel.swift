import SwiftUI

// A compact retro recorder: wood frame, one analog VU meter, a source bar, a chrome record
// button, a name field, a digit counter and a speaker grille.

struct RecorderPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 13) {
            VUMeter(level: model.recorder.isRecording ? model.recorder.level : 0)
                .frame(height: 82)
                .overlay(DragHandle())
            HStack(spacing: 14) {
                SourcePicker()
                RecordButton(isRecording: model.recorder.isRecording) { model.toggleRecording() }
            }
            HStack(spacing: 10) {
                NameField(text: $model.recordingName, onReveal: model.revealLastRecording)
                DigitTimer(seconds: model.recorder.elapsed)
                SettingsButton()
            }
            Grille().overlay(DragHandle())
        }
        .padding(15)
        .background(InnerPanel().overlay(DragHandle()))
        .padding(10)
        .background(WoodFrame().overlay(DragHandle()))
        .frame(width: 400)
    }
}

// MARK: - Frame

struct WoodFrame: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color(hex: 0xE0954E), Color(hex: 0xC4702F), Color(hex: 0xB05F24),
                                          Color(hex: 0xC97836)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(WoodGrain().clipShape(shape))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .black.opacity(0.45)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
    }
}

struct WoodGrain: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 11)
            for _ in 0..<90 {
                var y = rng.next() * size.height
                var x: CGFloat = -10
                var p = Path()
                p.move(to: CGPoint(x: x, y: y))
                let wobble = 0.6 + rng.next() * 2.4
                while x < size.width + 10 {
                    x += 14
                    y += (rng.next() - 0.5) * wobble
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                let dark = rng.next() > 0.35
                ctx.stroke(p, with: .color((dark ? Color(hex: 0x6B300C) : Color(hex: 0xF6B070))
                                            .opacity(0.08 + rng.next() * 0.16)),
                           lineWidth: 0.4 + rng.next() * 1.4)
            }
        }
    }
}

struct InnerPanel: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color(hex: 0x3B3B3B), Color(hex: 0x2A2A2A), Color(hex: 0x222222)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Color.black.opacity(0.85), lineWidth: 2))
            .overlay(shape.inset(by: 2).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}

// MARK: - VU meter

/// Where things sit on the meter face. The scale is an arc around a pivot below the face.
private struct MeterGeometry {
    let size: CGSize
    var radius: CGFloat { size.width * 0.86 }
    var pivot: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.40 + radius) }
    let maxAngle = 26.0 * .pi / 180

    /// A VU scale is linear in amplitude: 0 VU sits about 70% of the way across, +3 at the end.
    static func fraction(db: Double) -> Double { pow(10, db / 20) / pow(10, 3.0 / 20) }

    func angle(_ fraction: Double) -> Double { -maxAngle + fraction * 2 * maxAngle }
    func angle(db: Double) -> Double { angle(Self.fraction(db: db)) }

    func point(_ angle: Double, _ r: CGFloat) -> CGPoint {
        CGPoint(x: pivot.x + CGFloat(sin(angle)) * r, y: pivot.y - CGFloat(cos(angle)) * r)
    }

    func arc(from a0: Double, to a1: Double, r: CGFloat) -> Path {
        var p = Path()
        let steps = 40
        for i in 0...steps {
            let pt = point(a0 + (a1 - a0) * Double(i) / Double(steps), r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

struct VUMeter: View {
    /// Linear RMS level of the audio, 0...1.
    let level: Float

    /// Streamed audio is mastered around -14 to -20 dBFS RMS; put -15 dBFS at 0 VU.
    private var needleFraction: Double {
        guard level > 0 else { return -0.03 }
        let vu = 20 * log10(Double(level)) + 15
        return min(max(MeterGeometry.fraction(db: vu), -0.03), 1.06)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack {
            Canvas { ctx, size in Self.drawFace(ctx, MeterGeometry(size: size)) }
            Needle(fraction: needleFraction)
                .stroke(Color(hex: 0xEC5A22), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .shadow(color: .black.opacity(0.7), radius: 1.2, x: 1.5, y: 1.5)
                .animation(.interpolatingSpring(stiffness: 140, damping: 15), value: needleFraction)
            // The dark dome that hides the needle's pivot.
            GeometryReader { geo in
                Ellipse()
                    .fill(RadialGradient(colors: [Color(hex: 0x2C2C2C), Color(hex: 0x111111)],
                                         center: .top, startRadius: 2, endRadius: geo.size.width * 0.22))
                    .overlay(Ellipse().strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
                    .frame(width: geo.size.width * 0.38, height: geo.size.height * 0.5)
                    .position(x: geo.size.width / 2, y: geo.size.height * 1.02)
            }
            // Glass.
            LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.black, lineWidth: 1.5))
        .overlay(shape.inset(by: -1.5).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private static func drawFace(_ ctx: GraphicsContext, _ g: MeterGeometry) {
        let size = g.size
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(hex: 0x1C1C1C), Color(hex: 0x080808)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

        let r = g.radius
        let grey = Color(hex: 0xBDBDBD)
        let red = Color(hex: 0xA3261A)
        // Main scale band: grey up to 0 VU, red beyond.
        ctx.stroke(g.arc(from: g.angle(db: -20), to: g.angle(db: 0), r: r), with: .color(grey), lineWidth: 7)
        ctx.stroke(g.arc(from: g.angle(db: 0), to: g.angle(1.0), r: r), with: .color(red), lineWidth: 7)
        // Secondary inner scale.
        ctx.stroke(g.arc(from: g.angle(db: -20), to: g.angle(db: -7.4), r: r - 14),
                   with: .color(grey.opacity(0.75)), lineWidth: 4)
        ctx.stroke(g.arc(from: g.angle(db: -6.4), to: g.angle(db: -1.6), r: r - 14),
                   with: .color(grey.opacity(0.75)), lineWidth: 4)

        let marks: [(String, Double, Bool)] = [("-20", -20, false), ("-10", -10, false), ("-7", -7, false),
                                               ("-5", -5, false), ("-3", -3, false),
                                               ("0", 0, true), ("2", 2, true), ("3", 3, true)]
        for (label, db, hot) in marks {
            let text = Text(label)
                .font(.custom("GillSans-Bold", size: 11))
                .foregroundColor(hot ? Color(hex: 0xD2391F) : Color(hex: 0xD0D0D0))
            ctx.draw(text, at: g.point(g.angle(db: db), r + 12))
        }
        // Yellow minus, red plus in the top corners.
        ctx.fill(Path(roundedRect: CGRect(x: 14, y: 11, width: 9, height: 3), cornerRadius: 1),
                 with: .color(Color(hex: 0xE9D44C)))
        ctx.draw(Text("+").font(.system(size: 14, weight: .heavy)).foregroundColor(Color(hex: 0xD2391F)),
                 at: CGPoint(x: size.width - 18, y: 13))
        // Maker's mark.
        ctx.draw(Text("EARSHOT").font(.custom("GillSans-Bold", size: 10)).tracking(2.5)
                    .foregroundColor(Color(hex: 0x8C8C8C)),
                 at: CGPoint(x: size.width / 2, y: size.height * 0.40 + 25))
    }
}

private struct Needle: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let g = MeterGeometry(size: rect.size)
        let a = g.angle(fraction)
        var p = Path()
        p.move(to: g.point(a, g.radius * 0.6))
        p.addLine(to: g.point(a, g.radius + 6))
        return p
    }
}

// MARK: - Source

struct SourcePicker: View {
    @Environment(AppModel.self) private var model
    @State private var apps: (playing: [AppSource], other: [AppSource]) = ([], [])

    var body: some View {
        Menu {
            Button { model.source = .allApps } label: {
                Label("All Apps", systemImage: "square.grid.2x2")
            }
            if !apps.playing.isEmpty {
                Section("Playing Sound") { ForEach(apps.playing) { item($0) } }
            }
            Section("Running Apps") { ForEach(apps.other) { item($0) } }
        } label: {
            SourceLabel(source: model.source)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(model.recorder.isRecording)
        .onAppear(perform: refresh)
        .onHover { if $0 { refresh() } }
    }

    private func item(_ app: AppSource) -> some View {
        Button { model.source = .app(app) } label: {
            Label { Text(app.name) } icon: { Image(nsImage: app.icon.resized(16)) }
        }
    }

    private func refresh() {
        guard !model.recorder.isRecording else { return }
        apps = AudioProcesses.runningApps()
    }
}

struct SourceLabel: View {
    let source: CaptureSource

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 9) {
            Text("SOURCE:")
                .font(.custom("GillSans-SemiBold", size: 13))
                .tracking(2)
                .foregroundStyle(Color(hex: 0xD6D6D6))
                .shadow(color: .black, radius: 0, y: -1)
            icon.frame(width: 24, height: 24)
            Text(source.label)
                .font(.custom("GillSans", size: 21))
                .foregroundStyle(Color(hex: 0xF4F4F4))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Triangle()
                .fill(Color(hex: 0xD4D4D4))
                .frame(width: 14, height: 8)
        }
        .padding(.horizontal, 15)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .background(shape.fill(LinearGradient(colors: [Color(hex: 0x323232), Color(hex: 0x1D1D1D),
                                                       Color(hex: 0x252525)],
                                              startPoint: .top, endPoint: .bottom)))
        .overlay(shape.inset(by: 4).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color(hex: 0xD49762), Color(hex: 0x9C5A2B)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 3))
        .overlay(shape.inset(by: -1.5).strokeBorder(Color.black.opacity(0.8), lineWidth: 1))
        .shadow(color: Color(hex: 0xC27A42).opacity(0.35), radius: 4)
        .contentShape(shape)
    }

    @ViewBuilder private var icon: some View {
        switch source {
        case .allApps:
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 17))
                .foregroundStyle(Color(hex: 0xBBBBBB))
        case .app(let app):
            Image(nsImage: app.icon.resized(48)).resizable()
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Record button

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void
    @State private var glow = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.black.opacity(0.55)).frame(width: 60, height: 60).blur(radius: 2).offset(y: 2)
                // Brushed chrome.
                Circle()
                    .fill(AngularGradient(colors: [Color(hex: 0xF5F5F5), Color(hex: 0x8E8E8E), Color(hex: 0xE6E6E6),
                                                   Color(hex: 0x7A7A7A), Color(hex: 0xF0F0F0), Color(hex: 0x9C9C9C),
                                                   Color(hex: 0xF5F5F5)],
                                          center: .center))
                    .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.25), .clear, .black.opacity(0.25)],
                                                          center: .topLeading, startRadius: 4, endRadius: 60)))
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .black.opacity(0.6)],
                                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .frame(width: 56, height: 56)
                // Ruby lamp.
                Circle()
                    .fill(RadialGradient(colors: isRecording
                                         ? [Color(hex: 0xFF7A55), Color(hex: 0xE0200F), Color(hex: 0x6E0703)]
                                         : [Color(hex: 0x8A1A0C), Color(hex: 0x480904), Color(hex: 0x1E0201)],
                                         center: UnitPoint(x: 0.45, y: 0.42), startRadius: 1, endRadius: 15))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.75), lineWidth: 2))
                    .overlay(Ellipse().fill(Color.white.opacity(isRecording ? 0.5 : 0.28))
                        .frame(width: 10, height: 5).offset(x: -2, y: -7).blur(radius: 0.7))
                    .frame(width: 26, height: 26)
                    .shadow(color: Color(hex: 0xFF3010).opacity(isRecording ? (glow ? 0.95 : 0.45) : 0),
                            radius: isRecording ? 9 : 0)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Stop recording" : "Start recording")
        .onChange(of: isRecording) { _, on in
            if on {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glow = true }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { glow = false }
            }
        }
    }
}

// MARK: - Bottom row

struct NameField: View {
    @Binding var text: String
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField("My Recording", text: $text)
                .textFieldStyle(.plain)
                .font(.custom("GillSans", size: 17))
                .foregroundStyle(Color(hex: 0xE2E2E2))
            Button(action: onReveal) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8C8C8C))
            }
            .buttonStyle(.plain)
            .help("Show the last recording in Finder")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x1E1E1E)))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.7), lineWidth: 1))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).offset(y: 1)
        }
    }
}

struct DigitTimer: View {
    let seconds: TimeInterval

    var body: some View {
        let s = Int(seconds)
        let h = min(s / 3600, 9), m = s / 60 % 60, sec = s % 60
        HStack(spacing: 2) {
            tile(h)
            colon
            tile(m / 10); tile(m % 10)
            colon
            tile(sec / 10); tile(sec % 10)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x141414)))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func tile(_ d: Int) -> some View {
        Text("\(d)")
            .font(.custom("GillSans-SemiBold", size: 19))
            .foregroundStyle(Color(hex: 0xEEEEEE))
            .frame(width: 15, height: 26)
            .background(RoundedRectangle(cornerRadius: 2).fill(
                LinearGradient(stops: [.init(color: Color(hex: 0x444444), location: 0),
                                       .init(color: Color(hex: 0x2C2C2C), location: 0.5),
                                       .init(color: Color(hex: 0x1C1C1C), location: 0.5),
                                       .init(color: Color(hex: 0x292929), location: 1)],
                               startPoint: .top, endPoint: .bottom)))
            .overlay(Rectangle().fill(Color.black.opacity(0.6)).frame(height: 1))
    }

    private var colon: some View {
        Text(":").font(.custom("GillSans-Bold", size: 13)).foregroundStyle(Color(hex: 0x7C7C7C))
    }
}

struct SettingsButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 26))
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xD8D8D8), Color(hex: 0x8A8A8A)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recordings").font(.headline)
                Text(model.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Text("Saved as AAC (.m4a), 128 kbps stereo: about 1 MB per minute.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Recordings Folder") { NSWorkspace.shared.open(model.folder) }
                Divider()
                PermissionRow()
            }
            .padding(16)
            .frame(width: 300)
        }
    }
}

struct PermissionRow: View {
    @State private var status = AudioCapturePermission.status()

    var body: some View {
        HStack {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status == .granted ? .green : .orange)
            Text(status == .granted ? "Allowed to record app audio" : "Not allowed to record app audio yet")
                .font(.callout)
            Spacer()
            if status != .granted {
                Button("Fix…") { AudioCapturePermission.openSettings() }
            }
        }
        .onAppear { status = AudioCapturePermission.status() }
    }
}

struct Grille: View {
    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { _ in
                Capsule()
                    .fill(Color(hex: 0x0B0B0B))
                    .frame(height: 4)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 1).offset(y: 1.5)
                    }
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension NSImage {
    func resized(_ side: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: side, height: side))
        img.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        img.unlockFocus()
        return img
    }
}

/// Deterministic random numbers, so the wood grain looks the same every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

/// Lets you drag the borderless window from the parts of the panel that aren't controls.
struct DragHandle: NSViewRepresentable {
    final class View: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ nsView: View, context: Context) {}
}
