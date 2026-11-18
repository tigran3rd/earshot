import SwiftUI

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
