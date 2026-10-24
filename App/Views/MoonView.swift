import SwiftUI

/// The lit part of the moon, drawn from its phase.
private struct LitMoon: Shape {
    let phase: MoonPhase

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // The right side is lit while the moon grows, the left side while it shrinks.
        let side: CGFloat = phase.isWaxing ? 1 : -1
        let terminator = CGFloat(phase.terminator)
        let steps = 48

        var path = Path()
        // Down the lit edge, from the top to the bottom.
        for step in 0...steps {
            let t = Double.pi * Double(step) / Double(steps)
            let point = CGPoint(
                x: center.x + side * radius * CGFloat(sin(t)),
                y: center.y - radius * CGFloat(cos(t))
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        // Back up along the line between light and dark.
        for step in 0...steps {
            let t = Double.pi - Double.pi * Double(step) / Double(steps)
            path.addLine(to: CGPoint(
                x: center.x + side * terminator * radius * CGFloat(sin(t)),
                y: center.y - radius * CGFloat(cos(t))
            ))
        }
        path.closeSubpath()
        return path
    }
}

/// A small moon. The lit part is brighter than the dark part, so it reads by brightness and not by color.
struct MoonGlyph: View {
    let phase: MoonPhase
    var lit: Color = Theme.ink
    var shade: Color = Theme.line
    var outline: Color = Theme.inkTertiary

    var body: some View {
        ZStack {
            Circle().fill(shade)
            LitMoon(phase: phase).fill(lit)
            Circle().strokeBorder(outline, lineWidth: 0.75)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A small moon and the name of its phase, for the date of an entry.
struct MoonLabel: View {
    let date: Date
    @ScaledMetric(relativeTo: .subheadline) private var glyphSize: CGFloat = 12

    var body: some View {
        let phase = MoonPhase(on: date)
        HStack(spacing: 5) {
            MoonGlyph(phase: phase)
                .frame(width: glyphSize, height: glyphSize)
            Text(phase.name)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Moon: \(phase.name)")
    }
}
