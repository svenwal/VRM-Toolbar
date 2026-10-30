import SwiftUI

/// Liquid Glass on macOS 26, falling back to materials on older systems.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 22
    var tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint?.opacity(0.22)), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        }
    }
}

struct GlassButton: ViewModifier {
    var prominent = false
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}

extension View {
    func glassCard(radius: CGFloat = 22, tint: Color? = nil) -> some View { modifier(GlassCard(radius: radius, tint: tint)) }
    func glassButton(prominent: Bool = false) -> some View { modifier(GlassButton(prominent: prominent)) }
}

/// Slowly drifting mesh gradient; its mood follows the battery level.
struct AuroraBackground: View {
    var level: Double?

    private var accent: Color {
        guard let level else { return Color(red: 0.25, green: 0.45, blue: 1.0) }
        if level > 0.6 { return Color(red: 0.1, green: 0.85, blue: 0.6) }
        if level > 0.3 { return Color(red: 1.0, green: 0.7, blue: 0.2) }
        return Color(red: 1.0, green: 0.3, blue: 0.35)
    }

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.05, blue: 0.11)
            if #available(macOS 15.0, *) {
                TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate * 0.25
                    let d = { (a: Double, f: Double) in Float(sin(t * f + a) * 0.08) }
                    MeshGradient(width: 3, height: 3, points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5 + d(0, 1)], [0.5 + d(1, 1.3), 0.5 + d(2, 0.9)], [1, 0.5 + d(3, 1.1)],
                        [0, 1], [0.5, 1], [1, 1],
                    ], colors: [
                        .clear, accent.opacity(0.35), .clear,
                        Color(red: 0.1, green: 0.2, blue: 0.6).opacity(0.5), .clear, accent.opacity(0.45),
                        .clear, Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.35), .clear,
                    ])
                }
                .animation(.easeInOut(duration: 1.5), value: level)
            } else {
                LinearGradient(colors: [accent.opacity(0.35), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
            }
        }
        .ignoresSafeArea()
    }
}

/// Circular gauge used for battery level.
struct RingGauge: View {
    var value: Double?
    var tint: Color
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value ?? 0)
                .stroke(AngularGradient(colors: [tint.opacity(0.5), tint], center: .center, startAngle: .zero, endAngle: .degrees(360 * (value ?? 0))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.7), radius: 8)
                .animation(.smooth(duration: 0.8), value: value)
            if let value {
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            } else {
                Image(systemName: "bolt.fill").font(.system(size: 34)).foregroundStyle(tint)
            }
        }
    }
}

extension Color {
    /// Green → amber → red by battery level.
    static func battery(_ level: Double?) -> Color {
        guard let level else { return Color(red: 0.35, green: 0.8, blue: 1) }
        if level > 0.6 { return Color(red: 0.2, green: 0.9, blue: 0.6) }
        if level > 0.3 { return Color(red: 1, green: 0.75, blue: 0.25) }
        return Color(red: 1, green: 0.35, blue: 0.4)
    }
}
