import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, accessibility, finish
}

struct OnboardingView: View {
    let state: AppState
    let onDone: () -> Void
    @State private var step: OnboardingStep

    init(state: AppState, initialStep: OnboardingStep, onDone: @escaping () -> Void) {
        self.state = state
        self.onDone = onDone
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .accessibility: AccessibilityStep(state: state)
                case .finish: FinishStep(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 560, height: 470)
        .onReceive(NotificationCenter.default.publisher(for: .onboardingJump)) { note in
            if let target = note.object as? OnboardingStep { go(to: target) }
        }
    }

    private var footer: some View {
        HStack {
            PageDots(current: step)
            Spacer()
            if step != .welcome {
                Button("Back") { go(to: OnboardingStep(rawValue: step.rawValue - 1)!) }
                    .controlSize(.large)
            }
            switch step {
            case .welcome:
                Button("Get Started") { go(to: .accessibility) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            case .accessibility:
                if state.isAccessibilityTrusted {
                    Button("Continue") { go(to: .finish) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Skip for Now") { go(to: .finish) }
                        .controlSize(.large)
                }
            case .finish:
                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func go(to target: OnboardingStep) {
        withAnimation(.smooth(duration: 0.3)) { step = target }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            Text("Welcome to LightSpot")
                .font(.largeTitle.weight(.semibold))
            Text("macOS 27 replaced the Spotlight magnifying glass in the menu bar with a Siri AI voice button. LightSpot puts a magnifying glass back.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 24)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Text("Click it to open the search bar, ready to type.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }
}

private struct AccessibilityStep: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(symbol: "hand.raised.fill", tint: .blue, title: "Allow LightSpot to open search")
            Text("LightSpot opens the search bar by pressing your Spotlight shortcut (\(state.shortcutDisplay)) for you. macOS only lets an app send keystrokes if you allow it in Accessibility settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("LightSpot never reads what you type or what's on your screen. It only presses that one shortcut, bringing itself to the front first so apps like Screen Sharing can't intercept it.", systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                HStack(spacing: 12) {
                    if state.isAccessibilityTrusted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Permission granted").font(.headline)
                            Text("You're all set.").foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Waiting for permission…").font(.headline)
                            Text("Turn on LightSpot in Privacy & Security → Accessibility.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !state.isAccessibilityTrusted {
                        Button("Open Settings") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(8)
                .animation(.smooth, value: state.isAccessibilityTrusted)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct FinishStep: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(symbol: "checkmark.seal.fill", tint: .green, title: "You're ready")
            Text("Look for the magnifying glass in your menu bar. Click it to search, or right-click it for Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open LightSpot at login")
                            Text("Keeps the icon in your menu bar after a restart.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    if let error = state.loginItemError {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                    if !state.isInApplicationsFolder {
                        Label("Move LightSpot to your Applications folder so it keeps working after a restart.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(8)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb").foregroundStyle(.yellow)
                Text("Can't see the icon? It may be hidden by the menu bar settings in System Settings → Menu Bar. You can always open LightSpot again from Applications to get to Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.isAccessibilityTrusted {
                Button {
                    SpotlightTrigger.open()
                } label: {
                    Label("Try It Now", systemImage: "magnifyingglass")
                }
                .controlSize(.large)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pieces

private struct StepHeader: View {
    let symbol: String
    let tint: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 11))
            Text(title).font(.title.weight(.semibold))
        }
    }
}

private struct PageDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: step == current ? 18 : 7, height: 7)
            }
        }
        .animation(.smooth, value: current)
    }
}
