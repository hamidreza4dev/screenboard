import SwiftUI

extension LockMode {
    var detail: String {
        switch self {
        case .keyboard: "Every key does nothing"
        case .screen: "Black, touch-proof display"
        case .trackpad: "Cursor and clicks frozen"
        }
    }
}

extension Set where Element == LockMode {
    /// "Keyboard, Screen and Trackpad", in a stable order.
    var displayList: String {
        let names = LockMode.allCases.filter(contains).map(\.title)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}

extension LockController {
    func isSelected(_ mode: LockMode) -> Binding<Bool> {
        Binding(
            get: { self.selection.contains(mode) },
            set: { on in
                if on { self.selection.insert(mode) } else { self.selection.remove(mode) }
            }
        )
    }

    var isDeepClean: Bool { activeModes == Set(availableModes) }

    /// Short phase key used to drive state-change animations.
    var phaseKey: String {
        if isLocked { return "locked" }
        return "idle"
    }
}

/// m:ss until `deadline`.
func clockText(until deadline: Date, now: Date) -> String {
    let remaining = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    return "\(remaining / 60):" + String(format: "%02d", remaining % 60)
}

extension View {
    /// State-change animation: smooth with no bounce, or a plain cross-fade
    /// under Reduce Motion.
    func phaseAnimation(_ value: String, reduceMotion: Bool) -> some View {
        animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: value)
    }
}

/// Three Esc keycaps that light up as Escape is pressed toward the unlock.
struct EscKeycaps: View {
    let count: Int
    /// Light keycaps for the black screen shield.
    var onBlack = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                let pressed = i < count
                Text("esc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(pressed ? pressedText : idleText)
                    .frame(width: 36, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(pressed ? pressedFill : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(pressed ? pressedFill : idleLine, lineWidth: 1.5)
                    )
            }
        }
        .animation(.easeOut(duration: 0.15), value: count)
        .accessibilityElement()
        .accessibilityLabel("Escape pressed \(count) of 3 times")
    }

    private var pressedFill: Color { onBlack ? .white.opacity(0.85) : .accentColor }
    private var pressedText: Color { onBlack ? .black : .white }
    private var idleLine: Color { onBlack ? .white.opacity(0.25) : DeviceDiagram.line }
    private var idleText: Color { onBlack ? .white.opacity(0.55) : .secondary }
}
