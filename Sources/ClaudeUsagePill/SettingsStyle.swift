import SwiftUI

/// Direction-2 ("soft like the pill") styling vocabulary shared by every
/// settings page: radius-16 cards with a soft white fill, capsule text
/// fields, capsule pop-ups and capsule buttons. Native ColorPicker wells and
/// Toggles stay native — only the chrome around them is ours.
enum SettingsStyle {
    static let cardFill = Color.white.opacity(0.06)
    static let fieldFill = Color.black.opacity(0.30)
    static let hairline = Color.white.opacity(0.10)
    static let divider = Color.white.opacity(0.08)
    static let pageWidth: CGFloat = 380
}

// MARK: - Card

/// One grouped card: rows stacked with hairline dividers between them,
/// radius-16 white-6% fill (the pill's softness at settings scale).
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(SettingsStyle.cardFill))
    }
}

/// Hairline divider between card rows.
struct CardDivider: View {
    var body: some View {
        Rectangle().fill(SettingsStyle.divider).frame(height: 1)
    }
}

/// Section header caption above a card (Form-header replacement).
struct CardHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 14)
    }
}

/// Footnote caption under a card (Form-footer replacement).
struct CardFooter: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Capsule fields

/// Plain-style text field inside a capsule (black 30%, hairline border).
struct CapsuleFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(SettingsStyle.fieldFill))
            .overlay(Capsule().stroke(SettingsStyle.hairline, lineWidth: 1))
    }
}

extension View {
    func capsuleField() -> some View { modifier(CapsuleFieldChrome()) }
}

// MARK: - Capsule buttons

/// Neutral capsule (Back / Cancel): white-8% fill, hairline border.
struct CapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .overlay(Capsule().stroke(SettingsStyle.hairline, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// Accent-filled capsule (Done / primary actions).
struct AccentCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.accentColor.opacity(isEnabled ? 1 : 0.4)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Capsule pop-up picker

/// Menu-backed pop-up wearing capsule chrome (replaces the bezeled
/// Picker(.menu) inside cards). Options carry their own labels so callers
/// keep Form-era wording.
struct CapsulePicker<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentLabel)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(SettingsStyle.fieldFill))
            .overlay(Capsule().stroke(SettingsStyle.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }
}

// MARK: - Page scaffold

/// Standard page frame: scrollable card stack + the bottom-right button row
/// every page shares (Back-style neutral capsules left of the accent
/// primary).
struct SettingsPage<Content: View, Buttons: View>: View {
    var scrolls = false
    var scrollHeight: CGFloat = 480
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            if scrolls {
                ScrollView {
                    cardStack
                }
                .frame(height: scrollHeight)
            } else {
                cardStack
            }
            HStack(spacing: 8) {
                Spacer()
                buttons
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: SettingsStyle.pageWidth)
    }

    private var cardStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
}
