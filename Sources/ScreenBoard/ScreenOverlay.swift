import AppKit
import SwiftUI

/// Borderless window that can take key status (borderless windows refuse it
/// by default) and swallows every pointer/touch event instead of letting it
/// fall through to the windows below.
private final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown, .keyUp, .flagsChanged: super.sendEvent(event)
        default: break
        }
    }
}

/// One black shield per display, above everything else.
@MainActor
final class ScreenOverlay {
    private unowned let controller: LockController
    private var windows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?

    init(controller: LockController) {
        self.controller = controller
    }

    func show() {
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    func hide() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map(makeWindow)
        windows.first?.makeKeyAndOrderFront(nil)
        windows.dropFirst().forEach { $0.orderFrontRegardless() }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = ShieldWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.contentView = NSHostingView(rootView: OverlayView(controller: controller))
        window.setFrame(screen.frame, display: true)
        return window
    }
}

private struct OverlayView: View {
    let controller: LockController
    private let shownAt = Date()

    var body: some View {
        // Fade the hint after a few seconds so the pure-black screen shows
        // smudges clearly.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let faded = context.date.timeIntervalSince(shownAt) > 4 && controller.escapePresses == 0
            ZStack {
                Color.black
                VStack(spacing: 14) {
                    Text("Screen cleaning")
                        .font(.title3.weight(.medium))
                    EscKeycaps(count: controller.escapePresses, onBlack: true)
                    Text("Press Esc three times to finish")
                        .font(.callout)
                    if let deadline = controller.deadline {
                        CountdownText(deadline: deadline)
                            .font(.caption.monospacedDigit())
                    }
                }
                .foregroundStyle(.white.opacity(0.55))
                .opacity(faded ? 0.5 : 1)
                .animation(.easeInOut(duration: 1.2), value: faded)
            }
            .ignoresSafeArea()
        }
    }
}

struct CountdownText: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
            Text("Auto-unlock in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
        }
    }
}
