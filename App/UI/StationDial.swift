import SwiftUI

/// A railway-clock face: 60 bar indices, an optional white arc for the
/// ring window, long ticks for each ring, and the red signal disc parked at
/// twelve while a latch holds. Positions are fractions of one turn (0 = 12).
struct StationDial: View {
    var rings: [Double] = []
    var latched = false
    /// Index of the ring that is sounding now, drawn in signal red.
    var activeRing: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side / 2
            drawIndices(in: &context, center: center, radius: radius)
            drawWindow(in: &context, center: center, radius: radius)
            drawRings(in: &context, center: center, radius: radius)
        }
        .overlay {
            if latched {
                SignalDisc().transition(reduceMotion ? .opacity : .discRelease)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let state = latched ? "Latched" : "Not latched"
        return "\(state). \(rings.count) rings scheduled."
    }

    private func point(_ fraction: Double, _ r: CGFloat, _ c: CGPoint) -> CGPoint {
        let angle = fraction * 2 * .pi - .pi / 2
        return CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
    }

    private func bar(_ ctx: inout GraphicsContext, _ f: Double, _ outer: CGFloat, _ length: CGFloat,
                     _ width: CGFloat, _ color: Color, _ c: CGPoint) {
        var path = Path()
        path.move(to: point(f, outer, c))
        path.addLine(to: point(f, outer - length, c))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
    }

    private func drawIndices(in ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for i in 0..<60 {
            let major = i % 5 == 0
            bar(&ctx, Double(i) / 60, radius * 0.96, radius * (major ? 0.2 : 0.07),
                radius * (major ? 0.045 : 0.016), major ? Theme.face : Theme.graphite, center)
        }
    }

    private func drawWindow(in ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        guard let first = rings.first, let last = rings.last, last > first else { return }
        var arc = Path()
        arc.addArc(center: center, radius: radius * 0.52,
                   startAngle: .radians(first * 2 * .pi - .pi / 2),
                   endAngle: .radians(last * 2 * .pi - .pi / 2), clockwise: false)
        ctx.stroke(arc, with: .color(Theme.face.opacity(0.9)), style: StrokeStyle(lineWidth: radius * 0.06, lineCap: .round))
    }

    private func drawRings(in ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for (index, fraction) in rings.enumerated() {
            let active = index == activeRing
            bar(&ctx, fraction, radius * 0.73, radius * 0.2,
                radius * (active ? 0.05 : 0.028), active ? Theme.signal : Theme.face, center)
        }
    }
}

/// Release: the disc swings clockwise off twelve around the dial's centre and
/// fades as it goes, like the station clock's hand leaving its pause.
private struct DiscRelease: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(progress * 110))
            .opacity(1 - progress)
    }
}

extension AnyTransition {
    static var discRelease: AnyTransition {
        .modifier(active: DiscRelease(progress: 1), identity: DiscRelease(progress: 0))
    }
}

/// The red disc on its thin stem, parked at twelve. When the latch releases
/// it swings away clockwise (a crossfade under Reduce Motion).
private struct SignalDisc: View {
    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            ZStack {
                Rectangle()
                    .fill(Theme.signal)
                    .frame(width: r * 0.025, height: r * 0.9)
                    .offset(y: -r * 0.2)
                Circle()
                    .fill(Theme.signal)
                    .frame(width: r * 0.24, height: r * 0.24)
                    .offset(y: -r * 0.58)
                Circle()
                    .fill(Theme.signal)
                    .frame(width: r * 0.08, height: r * 0.08)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    StationDial(rings: [0.05, 0.07, 0.09, 0.11], latched: true, activeRing: 1)
        .padding(40)
        .background(Theme.enamel)
}
