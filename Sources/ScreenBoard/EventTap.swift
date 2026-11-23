import CoreGraphics
import Foundation
import os

/// A device that can be locked. Any combination can be locked at once.
enum LockMode: String, CaseIterable, Identifiable, Sendable {
    case keyboard, screen, trackpad
    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyboard: "Keyboard"
        case .screen: "Screen"
        case .trackpad: "Trackpad"
        }
    }

    var symbol: String {
        switch self {
        case .keyboard: "keyboard"
        case .screen: "display"
        case .trackpad: "rectangle.and.hand.point.up.left"
        }
    }
}

/// A HID-level CGEventTap running on its own thread. It swallows the input
/// classes for the locked devices and watches for Escape pressed three times in a
/// row (no other key in between) to end the lock.
final class EventTap: @unchecked Sendable {
    private struct State {
        var modes: Set<LockMode> = []
        var escCount = 0
        var lastEsc: UInt64 = 0
    }

    private static let escapeKeyCode: Int64 = 53
    private static let escapeWindowNanos: UInt64 = 1_500_000_000

    /// Raw CGEventType values that belong to the keyboard. 14 is
    /// NX_SYSDEFINED (media, brightness, volume keys).
    private static let keyboardTypes: Set<UInt32> = [10, 11, 12, 14]

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    /// Called on the main queue when Escape has been pressed three times.
    var onTripleEscape: (@Sendable () -> Void)?
    /// Called on the main queue with the number of Escape presses so far (0–2).
    var onEscapeProgress: (@Sendable (Int) -> Void)?

    var isRunning: Bool { tap != nil }

    /// True when the tap is live. A disabled tap gets one re-enable attempt
    /// first, so a timeout the callback hasn't handled yet isn't fatal.
    var isEnabled: Bool {
        guard let tap, CFMachPortIsValid(tap) else { return false }
        if CGEvent.tapIsEnabled(tap: tap) { return true }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Returns false if the tap could not be created (missing Accessibility
    /// permission).
    func start(modes: Set<LockMode>) -> Bool {
        stop()
        guard !modes.isEmpty else { return false }

        let mask: CGEventMask
        if modes == [.keyboard] {
            mask = Self.keyboardTypes.reduce(0) { $0 | (CGEventMask(1) << CGEventMask($1)) }
        } else {
            // All events: covers trackpad gestures, tablet/touch events and any
            // pointer-class types new hardware may introduce. Keyboard events
            // are needed too so Escape can be counted.
            mask = CGEventMask.max
        }

        state.withLock { $0 = State(modes: modes) }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            state.withLock { $0.modes = [] }
            return false
        }
        self.tap = tap

        // Run the tap on a dedicated thread so main-thread work can never
        // stall it into a timeout (which would leak keystrokes).
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
                ready.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()
            self.runLoop = loop
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        thread.name = "ScreenBoard.EventTap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        ready.wait()
        return true
    }

    func stop() {
        state.withLock { $0.modes = [] }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil
        runLoop = nil
        thread = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        let modes = state.withLock { $0.modes }
        guard !modes.isEmpty else { return pass }
        let raw = type.rawValue

        if Self.keyboardTypes.contains(raw) {
            if type == .keyDown || type == .keyUp {
                if event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode {
                    if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        registerEscape()
                    }
                    // Escape is reserved for unlocking while anything is locked.
                    return nil
                }
                if type == .keyDown { resetEscape() }
            }
            return modes.contains(.keyboard) ? nil : pass
        }

        // Everything that is not keyboard is pointer-class (mouse, trackpad,
        // gestures, tablet, touch). Screen mode drops it too so touches and
        // system edge gestures can't reach anything behind the overlay.
        return modes.contains(.screen) || modes.contains(.trackpad) ? nil : pass
    }

    private func resetEscape() {
        let hadPresses = state.withLock { s -> Bool in
            defer { s.escCount = 0 }
            return s.escCount > 0
        }
        if hadPresses, let onEscapeProgress {
            DispatchQueue.main.async { onEscapeProgress(0) }
        }
    }

    private func registerEscape() {
        let now = DispatchTime.now().uptimeNanoseconds
        let count = state.withLock { s -> Int in
            if now &- s.lastEsc > Self.escapeWindowNanos { s.escCount = 0 }
            s.escCount += 1
            s.lastEsc = now
            let count = s.escCount
            if count >= 3 { s.escCount = 0 }
            return count
        }
        if count >= 3 {
            if let onTripleEscape { DispatchQueue.main.async(execute: onTripleEscape) }
        } else if let onEscapeProgress {
            DispatchQueue.main.async { onEscapeProgress(count) }
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
