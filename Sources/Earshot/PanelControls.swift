import SwiftUI

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
