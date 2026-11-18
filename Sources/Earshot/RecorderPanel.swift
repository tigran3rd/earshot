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

// MARK: - Dragging

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
