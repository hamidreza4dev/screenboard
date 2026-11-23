import SwiftUI

/// A flat, line-drawn MacBook: display, keyboard and trackpad. Each part
/// shows its own state and, before a lock starts, toggles when clicked.
struct DeviceDiagram: View {
    @Bindable var controller: LockController
    // @State needs the SwiftUI macro plugin, which the Command Line Tools
    // lack; a shared observable model works with either toolchain.
    private let hover = DiagramHover.shared
    private var hovered: LockMode? { hover.mode }

    var body: some View {
        VStack(spacing: 3) {
            // Without a touch display there's no screen to clean, so the
            // drawing shows only the keyboard deck.
            if controller.hasTouchScreen {
                lid
                    .transition(.opacity)
            }
            deck
        }
        .animation(.smooth(duration: 0.3), value: controller.hasTouchScreen)
        .animation(.smooth(duration: 0.2), value: controller.selection)
        .animation(.smooth(duration: 0.2), value: hovered)
        // The toggles in the side pane carry the same controls for
        // VoiceOver and the keyboard.
        .accessibilityHidden(true)
    }

    // MARK: Parts

    private var lid: some View {
        let state = state(of: .screen)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(lineColor(for: .screen), lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.background)
            )
            .overlay {
                // Inner radius 4 = outer 10 − 6pt bezel.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(screenFill(state))
                    .overlay {
                        if state == .locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .transition(.opacity)
                        }
                    }
                    .padding(6)
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(lineColor(for: .screen))
                    .frame(width: 22, height: 3)
                    .padding(.top, 2)
            }
            .frame(width: 184, height: 120)
            .modifier(PartInteraction(mode: .screen, controller: controller, hover: hover))
    }

    private var deck: some View {
        VStack(spacing: 10) {
            Keys(fill: keyFill(state(of: .keyboard)))
                .frame(width: 192, height: 66)
                .padding(6)
                .contentShape(Rectangle())
                .background {
                    if hovered == .keyboard {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
                }
                .modifier(PartInteraction(mode: .keyboard, controller: controller, hover: hover))

            trackpad
        }
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(width: 216)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Self.line, lineWidth: 1.5)
        )
    }

    private var trackpad: some View {
        let state = state(of: .trackpad)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(trackpadFill(state))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(lineColor(for: .trackpad), lineWidth: 1.5)
            )
            .overlay {
                if state == .locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }
            }
            .frame(width: 84, height: 40)
            .modifier(PartInteraction(mode: .trackpad, controller: controller, hover: hover))
    }

    // MARK: State

    enum PartState { case idle, selected, locked, inactive }

    private func state(of mode: LockMode) -> PartState {
        if controller.isLocked {
            return controller.activeModes.contains(mode) ? .locked : .inactive
        }
        return controller.selection.contains(mode) ? .selected : .idle
    }

    static let line = Color.primary.opacity(0.22)

    private func lineColor(for mode: LockMode) -> Color {
        switch state(of: mode) {
        case .selected, .locked:
            return mode == .screen && state(of: mode) == .locked ? Self.line : .accentColor
        case .idle:
            return hovered == mode ? Color.primary.opacity(0.45) : Self.line
        case .inactive:
            return Color.primary.opacity(0.12)
        }
    }

    private func screenFill(_ state: PartState) -> Color {
        switch state {
        case .idle: Color.primary.opacity(0.06)
        case .selected: Color.accentColor.opacity(0.16)
        case .locked: .black
        case .inactive: Color.primary.opacity(0.03)
        }
    }

    private func keyFill(_ state: PartState) -> Color {
        switch state {
        case .idle: hovered == .keyboard ? Color.primary.opacity(0.18) : Color.primary.opacity(0.11)
        case .selected: Color.accentColor.opacity(0.4)
        case .locked: .accentColor
        case .inactive: Color.primary.opacity(0.05)
        }
    }

    private func trackpadFill(_ state: PartState) -> Color {
        switch state {
        case .idle: Color.primary.opacity(0.04)
        case .selected: Color.accentColor.opacity(0.16)
        case .locked: .accentColor
        case .inactive: .clear
        }
    }
}

/// The diagram part under the pointer.
@MainActor
@Observable
final class DiagramHover {
    static let shared = DiagramHover()
    var mode: LockMode?
}

/// Hover and click handling for one part of the diagram.
private struct PartInteraction: ViewModifier {
    let mode: LockMode
    let controller: LockController
    let hover: DiagramHover

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { inside in
                guard !controller.isLocked else { hover.mode = nil; return }
                if inside { hover.mode = mode } else if hover.mode == mode { hover.mode = nil }
            }
            .onTapGesture {
                guard !controller.isLocked else { return }
                if controller.selection.contains(mode) {
                    controller.selection.remove(mode)
                } else {
                    controller.selection.insert(mode)
                }
            }
            .help(controller.isLocked ? "" : "\(mode.title): click to select")
    }
}

/// A simplified Mac keyboard: a short function row and five rows of keys,
/// each row normalised to the same width.
private struct Keys: View {
    let fill: Color

    /// Relative key widths per row.
    private static let rows: [[CGFloat]] = [
        Array(repeating: 1, count: 14),
        Array(repeating: 1, count: 13) + [1.5],
        [1.5] + Array(repeating: 1, count: 13),
        [1.75] + Array(repeating: 1, count: 11) + [1.75],
        [2.25] + Array(repeating: 1, count: 10) + [2.25],
        [1, 1, 1, 1.25, 5.5, 1.25, 1, 1, 1.5],
    ]

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 2
            let fnHeight: CGFloat = 6
            let rowHeight = (size.height - fnHeight - gap * 5) / 5
            var y: CGFloat = 0
            for (index, row) in Self.rows.enumerated() {
                let height = index == 0 ? fnHeight : rowHeight
                let total = row.reduce(0, +)
                let unit = (size.width - gap * CGFloat(row.count - 1)) / total
                var x: CGFloat = 0
                for weight in row {
                    let rect = CGRect(x: x, y: y, width: unit * weight, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2, style: .continuous),
                                 with: .color(fill))
                    x += unit * weight + gap
                }
                y += height + gap
            }
        }
    }
}
