import SwiftUI

/// Station Clock: enamel black, clock-face white, one signal red that only
/// ever means "latched". Both use scenes (setting alarms at night, solving in
/// the morning) happen in a dark room, so the app is dark-only.
enum Theme {
    /// Enamel black ground of morning screens.
    static let enamel = Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x10 / 255)
    /// Bar indices, hands, primary text and the tint.
    static let face = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xEE / 255)
    /// Minor indices and secondary text on enamel (6.3:1).
    static let graphite = Color(red: 0x8A / 255, green: 0x8F / 255, blue: 0x98 / 255)
    /// The signal disc. Reserved for the latched state; never used for text.
    static let signal = Color(red: 0xE1 / 255, green: 0x25 / 255, blue: 0x1B / 255)

    static let radius: CGFloat = 12
}

/// The one button style: clock-white slab, black label, presses down.
struct SlabButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Theme.enamel)
            .background(Theme.face.opacity(isEnabled ? 1 : 0.35), in: .rect(cornerRadius: Theme.radius))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SlabButtonStyle {
    static var slab: SlabButtonStyle { SlabButtonStyle() }
}
