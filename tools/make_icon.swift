// Renders Earshot's app icon to Resources/AppIcon.icns.
// Run from the project root:  swift tools/make_icon.swift
import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

struct Rand {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) % 10_000) / 10_000
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            // macOS icon grid: 824pt body centred on a 1024 canvas.
            Color.clear
            body824.frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 10)
        }
        .frame(width: 1024, height: 1024)
    }

    var body824: some View {
        let outer = RoundedRectangle(cornerRadius: 185, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: 128, style: .continuous)
        return ZStack {
            // Wood.
            outer.fill(LinearGradient(colors: [Color(hex: 0xE89A52), Color(hex: 0xC4702F), Color(hex: 0xA65520),
                                               Color(hex: 0xC97836)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { ctx, size in
                var r = Rand(s: 99)
                for _ in 0..<160 {
                    var y = r.next() * size.height, x: CGFloat = -10
                    var p = Path(); p.move(to: CGPoint(x: x, y: y))
                    let w = 1 + r.next() * 6
                    while x < size.width + 10 { x += 24; y += (r.next() - 0.5) * w; p.addLine(to: CGPoint(x: x, y: y)) }
                    let dark = r.next() > 0.35
                    ctx.stroke(p, with: .color((dark ? Color(hex: 0x5E2808) : Color(hex: 0xFFB878)).opacity(0.08 + r.next() * 0.16)),
                               lineWidth: 1 + r.next() * 4)
                }
            }
            .clipShape(outer)
            outer.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .black.opacity(0.5)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 6)

            // Dark faceplate.
            inner.fill(LinearGradient(colors: [Color(hex: 0x3E3E3E), Color(hex: 0x262626), Color(hex: 0x1C1C1C)],
                                      startPoint: .top, endPoint: .bottom))
                .overlay(inner.strokeBorder(Color.black.opacity(0.9), lineWidth: 8))
                .overlay(inner.inset(by: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 3))
                .padding(58)

            meter.frame(width: 600, height: 270).position(x: 412, y: 262)

            // Speaker grille.
            VStack(spacing: 22) {
                ForEach(0..<5, id: \.self) { _ in
                    Capsule().fill(Color(hex: 0x0A0A0A)).frame(height: 15)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(Color.white.opacity(0.09)).frame(height: 3).offset(y: 5)
                        }
                }
            }
            .frame(width: 600)
            .position(x: 412, y: 600)

            recordButton.position(x: 412, y: 600)
        }
    }

    var meter: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x1E1E1E), Color(hex: 0x060606)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                let radius = size.width * 0.9
                let pivot = CGPoint(x: size.width / 2, y: size.height * 0.36 + radius)
                let maxA = 27.0 * .pi / 180
                func frac(_ db: Double) -> Double { pow(10, db / 20) / pow(10, 3.0 / 20) }
                func ang(_ f: Double) -> Double { -maxA + f * 2 * maxA }
                func pt(_ a: Double, _ r: CGFloat) -> CGPoint {
                    CGPoint(x: pivot.x + CGFloat(sin(a)) * r, y: pivot.y - CGFloat(cos(a)) * r)
                }
                func arc(_ a0: Double, _ a1: Double, _ r: CGFloat) -> Path {
                    var p = Path()
                    for i in 0...40 {
                        let q = pt(a0 + (a1 - a0) * Double(i) / 40, r)
                        i == 0 ? p.move(to: q) : p.addLine(to: q)
                    }
                    return p
                }
                ctx.stroke(arc(ang(frac(-20)), ang(frac(0)), radius), with: .color(Color(hex: 0xC4C4C4)), lineWidth: 26)
                ctx.stroke(arc(ang(frac(0)), ang(1), radius), with: .color(Color(hex: 0xB3281A)), lineWidth: 26)
                ctx.stroke(arc(ang(frac(-20)), ang(frac(-2)), radius - 48), with: .color(Color(hex: 0xC4C4C4).opacity(0.7)),
                           lineWidth: 12)
                // Ticks.
                for db in [-20.0, -10, -7, -5, -3, 0, 2, 3] {
                    var p = Path()
                    p.move(to: pt(ang(frac(db)), radius + 18)); p.addLine(to: pt(ang(frac(db)), radius + 44))
                    ctx.stroke(p, with: .color(db >= 0 ? Color(hex: 0xD63A20) : Color(hex: 0xD0D0D0)), lineWidth: 7)
                }
                // Needle, a little past 0 VU.
                let a = ang(0.62)
                var n = Path(); n.move(to: pt(a, radius * 0.55)); n.addLine(to: pt(a, radius + 30))
                ctx.stroke(n, with: .color(.black.opacity(0.6)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                n = Path(); n.move(to: pt(a, radius * 0.55)); n.addLine(to: pt(a, radius + 30))
                ctx.stroke(n, with: .color(Color(hex: 0xF05A22)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                // Pivot dome.
                ctx.fill(Path(ellipseIn: CGRect(x: size.width / 2 - 120, y: size.height - 62, width: 240, height: 130)),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0x333333), Color(hex: 0x0E0E0E)]),
                                               center: CGPoint(x: size.width / 2, y: size.height - 62),
                                               startRadius: 4, endRadius: 130))
            }
            LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.black, lineWidth: 7))
        .overlay(shape.inset(by: -5).strokeBorder(Color.white.opacity(0.10), lineWidth: 3))
    }

    var recordButton: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.6)).frame(width: 290, height: 290).blur(radius: 10).offset(y: 10)
            Circle()
                .fill(AngularGradient(colors: [Color(hex: 0xF7F7F7), Color(hex: 0x8A8A8A), Color(hex: 0xE8E8E8),
                                               Color(hex: 0x767676), Color(hex: 0xF2F2F2), Color(hex: 0x9A9A9A),
                                               Color(hex: 0xF7F7F7)], center: .center))
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.3), .clear, .black.opacity(0.3)],
                                                      center: .topLeading, startRadius: 10, endRadius: 300)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white, .black.opacity(0.7)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 4))
                .frame(width: 270, height: 270)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFF7A52), Color(hex: 0xD81C0C), Color(hex: 0x5E0603)],
                                     center: UnitPoint(x: 0.45, y: 0.4), startRadius: 4, endRadius: 75))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.8), lineWidth: 9))
                .overlay(Ellipse().fill(Color.white.opacity(0.55)).frame(width: 46, height: 22).offset(x: -10, y: -32)
                    .blur(radius: 3))
                .frame(width: 124, height: 124)
                .shadow(color: Color(hex: 0xFF3010).opacity(0.7), radius: 24)
        }
    }
}

func png(_ side: Int) -> Data {
    MainActor.assumeIsolated {
    let r = ImageRenderer(content: Icon())
    r.scale = CGFloat(side) / 1024
    let cg = r.cgImage!
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
    }
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
