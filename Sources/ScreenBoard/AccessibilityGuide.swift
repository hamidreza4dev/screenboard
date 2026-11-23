import AppKit
import SwiftUI

/// A small floating panel docked under System Settings that holds a
/// draggable ScreenBoard icon, so the user can drop the app straight into
/// the Accessibility list.
@MainActor
final class AccessibilityGuide {
    private var panel: NSPanel?
    private var trackTask: Task<Void, Never>?

    /// True from `show()` until access is granted or the user dismisses the
    /// guide. Stays true after a drop closes the panel, so the app still
    /// comes back to the front once the grant lands.
    private(set) var isWaiting = false

    func show() {
        isWaiting = true
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        guard panel == nil else { return }

        let hosting = NSHostingView(rootView: GuideView(
            onClose: { [weak self] in self?.hide() },
            onDropped: { [weak self] in self?.closePanel() }
        ))
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        // Panels hide when their app deactivates by default, and System
        // Settings takes focus as soon as it opens.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        position()
        panel.orderFrontRegardless()
        panel.invalidateShadow()

        // Follow the System Settings window as it opens, moves or resizes.
        trackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.position()
            }
        }
    }

    /// Dismisses the guide and stops waiting for the grant.
    func hide() {
        isWaiting = false
        closePanel()
    }

    /// Removes the panel but keeps waiting for the grant.
    private func closePanel() {
        trackTask?.cancel()
        trackTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: Placement

    private func position() {
        guard let panel else { return }
        let size = panel.frame.size
        let origin: NSPoint
        if let settings = Self.settingsWindowFrame(),
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(settings) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            var x = settings.midX - size.width / 2
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
            // Just under the window; overlap its bottom edge when there's no room.
            var y = settings.minY - 12 - size.height
            if y < visible.minY + 8 { y = settings.minY + 16 }
            origin = NSPoint(x: x, y: y)
        } else if let visible = NSScreen.main?.visibleFrame {
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 40)
        } else {
            return
        }
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }

    /// The frontmost System Settings window, in Cocoa screen coordinates.
    /// Window bounds and owner PIDs need no Screen Recording permission.
    private static func settingsWindowFrame() -> NSRect? {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                  kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        // The list is ordered front to back.
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 300, rect.height > 200
            else { continue }
            // CG uses a top-left origin on the primary display; Cocoa is bottom-left.
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        return nil
    }
}

// MARK: - View

private struct GuideView: View {
    let onClose: () -> Void
    let onDropped: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            dragWell

            VStack(alignment: .leading, spacing: 4) {
                Text("Drag ScreenBoard into the list")
                    .font(.headline)
                Text("Drop the icon on the list of apps above, then turn on its switch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .padding(.trailing, 18)
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("Close")
            .accessibilityLabel("Close")
        }
    }

    /// The app icon in a dashed well, with a nudging arrow toward the list.
    private var dragWell: some View {
        // Inner radius 6 = outer 14 − 8pt inset, so the icon sits concentric.
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(DeviceDiagram.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: 76, height: 76)
            .overlay {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 60, height: 60)
                    .allowsHitTesting(false)
            }
            .overlay(AppDragSource(onDropped: onDropped))
            .overlay(alignment: .top) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.accentColor))
                    .phaseAnimator(reduceMotion ? [0] : [0, -4]) { arrow, offset in
                        arrow.offset(y: offset)
                    } animation: { _ in .easeInOut(duration: 0.6) }
                    .offset(y: -10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .help("Drag into the list of apps")
            .accessibilityLabel("ScreenBoard app icon. Drag it into the list of apps in System Settings.")
    }
}

// MARK: - Drag source

/// An AppKit drag source for the app bundle. It accepts the first click, so
/// the drag works even though the panel never becomes key.
private struct AppDragSource: NSViewRepresentable {
    let onDropped: () -> Void

    func makeNSView(context: Context) -> AppDragView {
        let view = AppDragView()
        view.onDropped = onDropped
        return view
    }

    func updateNSView(_ nsView: AppDragView, context: Context) {
        nsView.onDropped = onDropped
    }
}

private final class AppDragView: NSView, NSDraggingSource {
    var onDropped: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    // Claim the mouse-down so the drag events come here.
    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        let url = Bundle.main.bundleURL as NSURL
        let item = NSDraggingItem(pasteboardWriter: url)
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let side: CGFloat = 60
        item.setDraggingFrame(NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2,
                                     width: side, height: side),
                              contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    /// A drop that System Settings accepted ends with a non-empty operation;
    /// one released anywhere else ends with none, and the panel stays.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        guard !operation.isEmpty else { return }
        onDropped?()
    }
}
