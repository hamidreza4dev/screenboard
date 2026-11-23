import SwiftUI

/// The main window: a drawing of the Mac on the left, native controls on the right.
struct ContentView: View {
    @Bindable var controller: LockController
    @AppStorage(LockController.failsafeKey) private var failsafeMinutes = LockController.defaultFailsafeMinutes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            stage
            Divider().ignoresSafeArea()
            pane
        }
        .frame(width: 640)
        // Same height idle and locked, so the window doesn't jump.
        .frame(minHeight: 450)
        // Pin the window to exactly this height so macOS can't restore a
        // stale, taller frame.
        .fixedSize(horizontal: false, vertical: true)
        .phaseAnimation(controller.phaseKey, reduceMotion: reduceMotion)
        .task {
            // Pick up the Accessibility grant as soon as the user flips it.
            while !Task.isCancelled {
                controller.refreshTrust()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Stage

    private var stage: some View {
        DeviceDiagram(controller: controller)
            .padding(.top, 20)
            .frame(width: 280)
            .frame(maxHeight: .infinity)
            .background(.quinary)
            .ignoresSafeArea()
    }

    // MARK: Pane

    private var pane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)

            if controller.isLocked {
                lockedStatus
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .transition(.opacity)
            } else {
                settings
                    .transition(.opacity)
            }

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                actions
                footer
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
                .contentTransition(.opacity)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
    }

    private var title: String {
        guard controller.isLocked else { return "What are you cleaning?" }
        return controller.isDeepClean ? "Everything is locked" : "\(controller.activeModes.displayList) locked"
    }

    private var subtitle: String {
        if controller.isLocked {
            return controller.activeModes.contains(.keyboard)
                ? "Wipe away. No key reaches your Mac."
                : "Wipe away. Nothing you touch reaches your Mac."
        }
        return "Locked parts ignore every touch. The rest keeps working."
    }

    // MARK: Idle

    private var settings: some View {
        Form {
            if !controller.isTrusted {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.lock.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ScreenBoard needs Accessibility access to lock input.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Open Privacy Settings…") { controller.requestAccessibility() }
                        }
                    }
                }
            }

            Section {
                ForEach(controller.availableModes, id: \.self) { mode in
                    Toggle(isOn: controller.isSelected(mode)) {
                        Text(mode.title)
                        Text(mode.detail)
                    }
                    .toggleStyle(.switch)
                }
            }

            Section {
                Picker("Auto-unlock after", selection: $failsafeMinutes) {
                    ForEach([1, 3, 5, 10], id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Locked

    private var lockedStatus: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let deadline = controller.deadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, deadline.timeIntervalSince(context.date))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Auto-unlock in")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(clockText(until: deadline, now: context.date))
                            .font(.system(size: 48, weight: .light).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                        ProgressView(value: remaining, total: max(controller.lockDuration, 1))
                            .progressViewStyle(.linear)
                            .accessibilityHidden(true)
                    }
                }
            }

            HStack(spacing: 12) {
                EscKeycaps(count: controller.escapePresses)
                Text("Press three times to unlock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if controller.isLocked {
                if controller.unlockAllowed {
                    Button { controller.stop() } label: {
                        Text("Unlock").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Button { controller.start(Set(controller.availableModes)) } label: {
                    Text("Lock All").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button { controller.start(controller.effectiveSelection) } label: {
                    Text("Start Cleaning").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(controller.effectiveSelection.isEmpty)
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var footer: some View {
        if let error = controller.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if !controller.isLocked {
            Text("Press Esc three times to unlock everything.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else if !controller.unlockAllowed {
            Text("The pointer is locked, so use Esc to finish.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
