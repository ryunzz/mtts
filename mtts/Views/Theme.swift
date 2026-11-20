import AppKit
import SwiftUI

/// Spacing and shape constants shared by every screen, so the app keeps one rhythm.
enum Layout {
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 18
    static let cardPadding: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let takeTarget = 10
    /// Click gesture takes to aim for: enough for the matcher to learn its spread.
    static let clickTakeTarget = ClickGestureMatcher.minimumTakes + 5
}

extension Color {
    /// White cards on the light window background; a faint lift in dark mode.
    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.05)
            : NSColor.white
    })
    static let cardBorder = Color(nsColor: .separatorColor)
    static let subtleFill = Color.primary.opacity(0.05)
}

extension HeadphoneStatus {
    var color: Color {
        switch self {
        case .streaming: .green
        case .waiting: .orange
        case .noHeadphones: .secondary
        case .unsupported, .denied, .unavailable: .red
        }
    }
}

/// A titled surface. Every screen is built from these.
struct Card<Content: View, Accessory: View>: View {
    private let title: String?
    private let caption: String?
    private let accessory: Accessory
    private let content: Content
    private var fillsHeight = false

    init(_ title: String? = nil, caption: String? = nil,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || Accessory.self != EmptyView.self {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title { Text(title).font(.headline) }
                        if let caption {
                            Text(caption).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    accessory
                }
            }
            content
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(Color.cardBorder, lineWidth: 0.5))
    }
}

extension Card {
    /// Stretches to the height of its row, so cards side by side line up.
    func fillingHeight() -> Card {
        var copy = self
        copy.fillsHeight = true
        return copy
    }
}

extension Card where Accessory == EmptyView {
    init(_ title: String? = nil, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, caption: caption, accessory: { EmptyView() }, content: content)
    }
}

/// A label over a large rounded number.
struct Metric: View {
    var title: String
    var value: String
    var unit: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusDot: View {
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .background(Circle().fill(color.opacity(0.25)).frame(width: 13, height: 13))
    }
}

/// A rounded square holding an SF Symbol — the app's icon treatment for devices.
struct SymbolTile: View {
    var symbol: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

/// Inline notice with an optional action, tinted by severity.
struct Banner<Actions: View>: View {
    var symbol: String
    var title: String
    var message: String
    var tint: Color
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.5))
    }
}

/// A keyboard key, for "Hold Space" hints.
struct KeyCap: View {
    var label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

private struct PageScrollsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Off when rendering a page to an image (`ImageRenderer` can't draw scroll views).
    var pageScrolls: Bool {
        get { self[PageScrollsKey.self] }
        set { self[PageScrollsKey.self] = newValue }
    }
}

/// A full-width page: scrolls, pads, and stacks cards.
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.pageScrolls) private var scrolls

    var body: some View {
        Group {
            if scrolls {
                ScrollView { stack }
            } else {
                stack
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            content
        }
        .padding(Layout.pagePadding)
        .frame(maxWidth: 1100, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

enum SystemSettings {
    static func open(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    static let bluetooth = "com.apple.BluetoothSettings"
    static let sound = "com.apple.Sound-Settings.extension"
    static let motionPrivacy = "com.apple.preference.security?Privacy_Motion"
}
