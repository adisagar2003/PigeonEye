import Contracts
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

    /// The confidence bands. Muted on purpose: these sit next to a document, not
    /// on a dashboard, and a saturated red beside a government letter reads as
    /// an error in the app rather than a doubt about a reading.
    ///
    /// Colour is never the only carrier — every ring is labelled with its word
    /// and its percentage, because roughly one man in twelve cannot separate
    /// this green from this amber.
    public static func band(_ band: Band) -> Color {
        switch band {
        case .green: Color(hex: 0x3F6B4F)
        case .amber: Color(hex: 0x8A6524)
        case .red: Color(hex: 0x9B4A3D)
        }
    }
}

/// How sure the reader is about one reading, as a ring.
///
/// **Urgency is about the document; confidence is about our reading of it.**
/// They never share a visual language (`project-overview.md` §5) — badge for one,
/// ring for the other, and this is the ring.
///
/// The word and the percentage sit beside it deliberately: a colour alone puts
/// the whole signal in a channel some readers do not have.
public struct ConfidenceRing: View {
    private let confidence: Confidence
    public init(_ confidence: Confidence) { self.confidence = confidence }

    public var body: some View {
        let colour = Ink.band(confidence.band)
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Ink.neutral300, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.02, confidence.score))
                    .stroke(colour, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 15, height: 15)

            Text("\(Int((confidence.score * 100).rounded()))%")
                .font(.mono(10.5)).foregroundStyle(colour)
        }
        .help(explain(confidence))
        .accessibilityLabel(
            "Confidence \(Int((confidence.score * 100).rounded())) percent, "
            + "\(confidence.band.rawValue). " + explain(confidence))
    }
}

/// What a ring means, in sentences, for the tooltip.
///
/// Built from the signals rather than from the score, because the score is
/// exactly the part that cannot be trusted upward (`architecture.md` §12). The
/// reader needs to know *why* something is or is not confirmed — showing them
/// the same number twice tells them nothing.
public func explain(_ confidence: Confidence) -> String {
    func value(_ name: String) -> Double? {
        confidence.signals.first { $0.name == name }?.value
    }
    var parts: [String] = []

    switch confidence.band {
    case .green: parts.append("Confirmed.")
    case .amber: parts.append("Read, but nothing confirms it.")
    case .red: parts.append("Doubtful — this is the kind of reading that gets escalated.")
    }

    switch value(Signal.validator) {
    case 1: parts.append("It has the shape this kind of value should have.")
    case 0: parts.append("It does not have the shape this kind of value should have, so it can never show as confirmed.")
    default: break
    }

    switch value(Signal.homoglyph) {
    case 1: parts.append("A second reading differs by look-alike characters (l/I, O/0) — the error that ruins names and numbers.")
    case 0: parts.append("The alternative readings agree.")
    default: break
    }

    if let ocr = value(Signal.ocr) {
        parts.append(
            "Text recognition scored it \(Int((ocr * 100).rounded()))%, which on its own is never enough — "
            + "the four highest scores in this corpus were all misread checkboxes.")
    }
    return parts.joined(separator: " ")
}

/// What the three colours mean, said once, above the list.
///
/// A colour with no key is decoration. This is also the second carrier for
/// readers who cannot separate the green from the amber: every swatch is
/// labelled, so nothing here depends on hue alone.
public struct ConfidenceLegend: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 13) {
            key(.green, "confirmed")
            key(.amber, "unconfirmed")
            key(.red, "doubtful")
        }
        .help("How sure we are of our reading — never a judgement about the document itself.")
    }

    private func key(_ band: Band, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().stroke(Ink.band(band), lineWidth: 2).frame(width: 8, height: 8)
            Text(label)
                .font(.body(10)).tracking(0.3).textCase(.uppercase)
                .foregroundStyle(Ink.neutral600)
        }
    }
}

/// What the reader shows when there is nothing trustworthy to score with —
/// **I4**. Not a zero and not an empty ring: "not scored" and "scored low" are
/// different claims, and a 0% ring says the second one.
public struct UnscoredMark: View {
    public init() {}
    public var body: some View {
        Text("not scored")
            .font(.mono(10)).foregroundStyle(Ink.neutral600)
            .help("No signal here but the model's own opinion of itself, which is never enough on its own.")
    }
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

public extension View {
    func blueprint(stroke: Color = Ink.divider, marks: Color = Ink.text.opacity(0.55)) -> some View {
        modifier(Blueprint(stroke: stroke, marks: marks))
    }

    /// Uppercase label set in the heading face, as the design uses everywhere.
    func kicker(_ size: CGFloat = 10, tracking: CGFloat = 0.9, color: Color = Ink.accent700) -> some View {
        font(.heading(size)).tracking(tracking).textCase(.uppercase).foregroundStyle(color)
    }
}
