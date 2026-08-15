import SwiftUI

// The design system's tokens, from `_ds/industry-.../styles.css`. One home for
// every colour and type ramp — a hex literal in a view is the duplicate that
// coding-standards.md §1.1 warns about.
//
// Fonts deviate deliberately: the design specifies Barlow and Barlow
// Condensed, both Google fonts, and downloading or bundling them contradicts
// the zero-dependency stack (architecture.md §5). The system font at
// `.width(.condensed)` fills the same typographic role with nothing to fetch.

public enum Ink {
    public static let bg = Color(hex: 0xF2F2F3)
    public static let surface = Color(hex: 0xE9E9EA)
    public static let text = Color(hex: 0x1D1F20)
    public static let accent = Color(hex: 0x5980A6)
    public static let divider = Color(hex: 0x1D1F20).opacity(0.16)

    public static let neutral100 = Color(hex: 0xF5F5F8)
    public static let neutral200 = Color(hex: 0xE7E7EA)
    public static let neutral300 = Color(hex: 0xD4D4D7)
    public static let neutral400 = Color(hex: 0xB7B7BA)
    public static let neutral500 = Color(hex: 0x98989B)
    public static let neutral600 = Color(hex: 0x7A7A7D)
    public static let neutral700 = Color(hex: 0x5D5D60)
    public static let neutral800 = Color(hex: 0x424244)
    public static let neutral900 = Color(hex: 0x2B2B2D)

    public static let accent100 = Color(hex: 0xEEF6FF)
    public static let accent200 = Color(hex: 0xD6EBFF)
    public static let accent300 = Color(hex: 0xB5D9FD)
    public static let accent400 = Color(hex: 0x94BCE3)
    public static let accent500 = Color(hex: 0x749DC4)
    public static let accent600 = Color(hex: 0x597EA3)
    public static let accent700 = Color(hex: 0x416180)
    public static let accent800 = Color(hex: 0x2C455D)
    public static let accent900 = Color(hex: 0x1D2D3D)

    /// How far a control dims while held. The design system has no pressed
    /// state, so this is the one place that decides — a literal inside a
    /// button style is the duplicate §1.1 warns about.
    public static let pressedOpacity = 0.55
}

public extension Font {
    /// Barlow Condensed's role: headings, labels, anything set in caps.
    static func heading(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - The blueprint frame

/// Square, hairline-bordered, with registration marks outside each corner.
/// Components in this system are wireframe objects, not cards.
public struct Blueprint: ViewModifier {
    var stroke: Color
    var marks: Color

    public func body(content: Content) -> some View {
        content
            .overlay(Rectangle().stroke(stroke, lineWidth: 1))
            .overlay(alignment: .topLeading) { mark(flipX: false, flipY: false) }
            .overlay(alignment: .topTrailing) { mark(flipX: true, flipY: false) }
            .overlay(alignment: .bottomLeading) { mark(flipX: false, flipY: true) }
            .overlay(alignment: .bottomTrailing) { mark(flipX: true, flipY: true) }
    }

    private func mark(flipX: Bool, flipY: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(marks).frame(width: 1, height: 11).offset(x: 5)
            Rectangle().fill(marks).frame(width: 11, height: 1).offset(y: 5)
        }
        .frame(width: 11, height: 11)
        .offset(x: flipX ? 6 : -6, y: flipY ? 6 : -6)
    }
}

// MARK: - Buttons

/// Every button in this app is a bordered label with no fill, and `.plain`
/// hit-tests only what is actually drawn — the glyph and the 1pt border. The
/// padded interior is empty, so a click 4pt away from the `+` fell straight
/// through to the view behind. `contentShape` makes the whole frame the
/// target, and it belongs here rather than at seven call sites.
public struct Flat: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? Ink.pressedOpacity : 1)
    }
}

public extension ButtonStyle where Self == Flat {
    static var flat: Flat { Flat() }
}

/// A list row that goes somewhere when clicked.
///
/// `Flat` is right for a control that already looks like one — a bordered label
/// reads as a button before you touch it. A row of text does not, and the rail
/// shipped two lists whose rows were indistinguishable from the transcript
/// until you happened to click one.
///
/// Three signals, because the one that matters is the one visible *before* the
/// mouse arrives: the pointer turns into a hand, the row fills under it, and
/// `Chevron` sits at the trailing edge at rest. Hover and cursor are feedback;
/// only the chevron is an affordance.
public struct Row: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        Hovering(configuration: configuration)
    }

    /// Hover is state, and a `ButtonStyle` cannot hold any — so the body is a
    /// real `View` rather than the usual inline chain.
    private struct Hovering: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                // Behind the label, so a selected row keeps its accent fill
                // while hovered rather than the two colours fighting.
                .background(hovering ? Ink.neutral200 : .clear)
                .opacity(configuration.isPressed ? Ink.pressedOpacity : 1)
                .onHover { hovering = $0 }
                .pointerStyle(.link)
        }
    }
}

public extension ButtonStyle where Self == Row {
    static var row: Row { Row() }
}

/// The "this row goes somewhere" mark, at the trailing edge of a `Row`.
///
/// Typographic rather than an SF Symbol: there is not one symbol anywhere else
/// in this app, and a single borrowed glyph reads as a different design system
/// leaking in. Muted, because it repeats on every row and the value beside it
/// is what the user came to read.
public struct Chevron: View {
    public init() {}
    public var body: some View {
        Text("›")
            .font(.heading(15))
            .foregroundStyle(Ink.neutral500)
            .accessibilityHidden(true)
    }
}

public extension View {
    func blueprint(stroke: Color = Ink.divider, marks: Color = Ink.text.opacity(0.55)) -> some View {
        modifier(Blueprint(stroke: stroke, marks: marks))
    }

    /// Uppercase label set in the heading face, as the design uses everywhere.
    func kicker(_ size: CGFloat = 10, tracking: CGFloat = 0.9, color: Color = Ink.accent700) -> some View {
        font(.heading(size)).tracking(tracking).textCase(.uppercase).foregroundStyle(color)
    }
}
