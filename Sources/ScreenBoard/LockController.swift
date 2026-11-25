import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class LockController {
    static let shared = LockController()

    static let failsafeKey = "failsafeMinutes"
    static let defaultFailsafeMinutes = 3
    private static let selectionKey = "selectedDevices"

    /// Devices the user has picked on the main screen (remembered).
    var selection: Set<LockMode> {
        didSet { UserDefaults.standard.set(selection.map(\.rawValue), forKey: Self.selectionKey) }
    }
    /// Devices that are locked right now.
    private(set) var activeModes: Set<LockMode> = []
    private(set) var deadline: Date?
    /// Length of the current lock, for progress displays.
    private(set) var lockDuration: TimeInterval = 0
    private(set) var escapePresses = 0
    var errorMessage: String?
    private(set) var isTrusted = AXIsProcessTrusted()
    /// Screen cleaning is only offered when a display takes touch input.
    private(set) var hasTouchScreen = LockController.detectTouchScreen()

    /// Devices this Mac can lock, in display order.
    var availableModes: [LockMode] {
        LockMode.allCases.filter { $0 != .screen || hasTouchScreen }
    }
    /// The remembered selection, minus devices this Mac doesn't have. The
    /// stored selection is kept, so Screen returns with a touch display.
    var effectiveSelection: Set<LockMode> { selection.intersection(availableModes) }

    var isLocked: Bool { !activeModes.isEmpty }
    /// The Unlock button is only reachable when the pointer still works.
    var unlockAllowed: Bool { !activeModes.contains(.screen) && !activeModes.contains(.trackpad) }
    var isBusy: Bool { isLocked }

    @ObservationIgnored private let tap = EventTap()
    @ObservationIgnored private lazy var overlay = ScreenOverlay(controller: self)
    @ObservationIgnored private let guide = AccessibilityGuide()
    @ObservationIgnored private var failsafeTask: Task<Void, Never>?
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    @ObservationIgnored private var savedPresentation: NSApplication.PresentationOptions = []
    @ObservationIgnored private var cursorHidden = false
    @ObservationIgnored private var isPreview = false

    private init() {
        // Keyboard is on by default; after that, the user's last choice wins,
        // including choosing nothing.
        let saved = UserDefaults.standard.stringArray(forKey: Self.selectionKey) ?? [LockMode.keyboard.rawValue]
        selection = Set(saved.compactMap(LockMode.init(rawValue:)))

        tap.onTripleEscape = { Task { @MainActor in LockController.shared.stop() } }
        tap.onEscapeProgress = { count in Task { @MainActor in LockController.shared.escapePresses = count } }

        // Taps don't work on the lock screen or across user switches, and
        // nobody is cleaning a sleeping Mac: always release.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification,
                     NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { LockController.shared.stop() }
            }
        }
        // A touch display can be plugged in or removed while the app runs.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { LockController.shared.refreshTouchScreen() }
        }
        applyPreviewArguments()
    }

    /// Screenshot support: `-previewState idle|locked -previewModes
    /// keyboard,trackpad` fakes a state without touching any input device.
    private func applyPreviewArguments() {
        let defaults = UserDefaults.standard
        guard let state = defaults.string(forKey: "previewState") else { return }
        isPreview = true
        isTrusted = defaults.bool(forKey: "previewUntrusted") ? false : true
        let modes = Set((defaults.string(forKey: "previewModes") ?? "")
            .split(separator: ",").compactMap { LockMode(rawValue: String($0)) })
        switch state {
        case "locked":
            activeModes = modes
            lockDuration = 180
            deadline = Date().addingTimeInterval(134)
            escapePresses = 1
        default:
            selection = modes
        }
    }

    var failsafeMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: Self.failsafeKey)
        return v > 0 ? min(v, 10) : Self.defaultFailsafeMinutes
    }

    func refreshTouchScreen() {
        hasTouchScreen = Self.detectTouchScreen()
    }

    /// `-previewTouchScreen YES|NO` overrides detection for one launch. It
    /// works with or without `-previewState`, and locking stays real.
    private static func detectTouchScreen() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "previewTouchScreen") != nil else { return TouchScreen.isAvailable }
        return defaults.bool(forKey: "previewTouchScreen")
    }

    // MARK: Permissions

    func refreshTrust() {
        guard !isPreview else { return }
        isTrusted = AXIsProcessTrusted()
        // Access granted while the drag guide was up: put it away and come
        // back to the front so the user can start right away.
        if isTrusted, guide.isWaiting {
            guide.hide()
            errorMessage = nil
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Opens Privacy & Security › Accessibility with a floating guide that
    /// holds a draggable app icon to drop into the list.
    func requestAccessibility() {
        isTrusted = AXIsProcessTrusted()
        guard !isTrusted else { return }
        guide.show()
    }

    private func preflight(_ modes: Set<LockMode>) -> Bool {
        refreshTrust()
        guard isTrusted else {
            errorMessage = "ScreenBoard needs Accessibility access to block input."
            requestAccessibility()
            return false
        }
        // With Secure Input on, taps receive no key events: keys would leak
        // through and the Escape exit would never be seen.
        if IsSecureEventInputEnabled() {
            errorMessage = "Secure Input is on (a password field or Terminal's Secure Keyboard Entry). Turn it off and try again."
            return false
        }
        return true
    }

    // MARK: Locking

    /// Locks `modes` immediately.
    func start(_ requested: Set<LockMode>) {
        let modes = requested.intersection(availableModes)
        guard !modes.isEmpty, !isLocked else { return }
        errorMessage = nil
        guard preflight(modes) else { return }
        guard tap.start(modes: modes) else {
            errorMessage = "Could not install the input blocker. Re-grant Accessibility access and try again."
            return
        }

        activeModes = modes
        escapePresses = 0

        if modes.contains(.screen) {
            NSApp.activate(ignoringOtherApps: true)
            savedPresentation = NSApp.presentationOptions
            NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching,
                                         .disableHideApplication, .disableAppleMenu]
            overlay.show()
        }
        if modes.contains(.trackpad) {
            // Dropping mouseMoved alone doesn't stop the cursor; detach it so
            // hover effects and hot corners can't fire either.
            CGAssociateMouseAndMouseCursorPosition(0)
        }
        if modes.contains(.screen) || modes.contains(.trackpad) {
            NSCursor.hide()
            cursorHidden = true
        }

        let minutes = failsafeMinutes
        lockDuration = TimeInterval(minutes * 60)
        deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        failsafeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isLocked else { return }
                // A tap whose trust was revoked can wedge input: bail out.
                if !AXIsProcessTrusted() {
                    self.stop()
                    self.errorMessage = "Accessibility access was revoked, so protection was turned off."
                    return
                }
                // Secure Input hides keys from the tap, which kills the Esc
                // exit for every device, not just the keyboard.
                if IsSecureEventInputEnabled() {
                    self.stop()
                    self.errorMessage = "Secure Input turned on, so protection was turned off."
                    return
                }
                // Never leave the overlay or a frozen cursor without a live tap.
                if !self.tap.isEnabled {
                    self.stop()
                    self.errorMessage = "The input blocker stopped unexpectedly, so protection was turned off."
                    return
                }
            }
        }
    }

    func stop() {
        guard isLocked else { return }
        let modes = activeModes
        tap.stop()
        failsafeTask?.cancel()
        watchdogTask?.cancel()
        failsafeTask = nil
        watchdogTask = nil
        deadline = nil
        activeModes = []
        escapePresses = 0

        if modes.contains(.screen) {
            overlay.hide()
            NSApp.presentationOptions = savedPresentation
        }
        if modes.contains(.trackpad) {
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
    }
}
