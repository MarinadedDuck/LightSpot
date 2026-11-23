import SwiftUI

struct SettingsView: View {
    let state: AppState
    @Bindable var updater: Updater
    let onShowWelcome: () -> Void

    static let repoURL = URL(string: "https://github.com/MarinadedDuck/LightSpot")!

    private static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Case Study Creative's apps page. UTM tags (as in PME) tell the site the visit came from
    /// LightSpot's Settings; they carry nothing about the user.
    static let moreAppsURL: URL = {
        var components = URLComponents(string: "https://www.casestudycreative.ca/apps")!
        components.queryItems = [
            URLQueryItem(name: "utm_source", value: "lightspot_app"),
            URLQueryItem(name: "utm_medium", value: "referral"),
            URLQueryItem(name: "utm_campaign", value: "settings"),
            URLQueryItem(name: "utm_content", value: shortVersion),
        ]
        return components.url!
    }()

    private var version: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(Self.shortVersion) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LightSpot").font(.title2.weight(.semibold))
                        Text(version).foregroundStyle(.secondary)
                        Text("Created by Kevin Luttman")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                if let error = state.loginItemError {
                    Text(error).foregroundStyle(.red)
                }
                LabeledContent("Spotlight shortcut") {
                    if state.shortcut.isEnabled {
                        Text(state.shortcutDisplay).monospaced()
                    } else {
                        Button("Turned Off – Fix…") { Permissions.openKeyboardShortcutsSettings() }
                    }
                }
            }

            Section {
                LabeledContent("Accessibility") {
                    if state.isAccessibilityTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow…") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Needed so LightSpot can press your Spotlight shortcut. LightSpot never reads keystrokes or screen contents.")
                    .foregroundStyle(.secondary)
            }

            if Updater.isEnabled {
                Section {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                } header: {
                    Text("Updates")
                } footer: {
                    Text("LightSpot checks GitHub for a new version once a day. Nothing about you or your Mac is sent.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Show Welcome Screen") { onShowWelcome() }
                Link("LightSpot on GitHub", destination: Self.repoURL)
                Link("Report an Issue", destination: Self.repoURL.appending(path: "issues"))
                Link("More Apps from Case Study Creative", destination: Self.moreAppsURL)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
