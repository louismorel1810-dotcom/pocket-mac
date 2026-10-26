import CoreGraphics
import SwiftUI

/// Appli compagnon : vit dans la barre des menus du Mac à piloter.
@main
struct CompanionApp: App {
    @StateObject private var server = Server()

    var body: some Scene {
        MenuBarExtra {
            CompanionMenu()
                .environmentObject(server)
        } label: {
            Image(systemName: server.connectedClient == nil ? "laptopcomputer" : "laptopcomputer.and.iphone")
        }
        .menuBarExtraStyle(.window)
    }
}

struct CompanionMenu: View {
    @EnvironmentObject private var server: Server
    @State private var accessibility = InputInjector.isTrusted
    @State private var screenRecording = CGPreflightScreenCaptureAccess()
    @State private var editedCode = ""

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pocket Mac").font(.headline)
            Label(server.status, systemImage: server.connectedClient == nil ? "antenna.radiowaves.left.and.right" : "checkmark.circle.fill")
                .foregroundStyle(server.connectedClient == nil ? Color.secondary : Color.green)

            GroupBox("Code à saisir sur l'iPhone") {
                HStack {
                    TextField("Code", text: $editedCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.title2, design: .monospaced))
                    Button("Valider") { server.passcode = editedCode }
                        .disabled(editedCode == server.passcode || editedCode.count < 4)
                }
            }

            GroupBox("Adresses de ce Mac") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Server.addresses(), id: \.self) { address in
                        Text(address + (address.hasPrefix("100.") ? "  (Tailscale, à distance)" : ""))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Text("Sur le même Wi-Fi, l'iPhone trouve ce Mac tout seul.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Autorisations") {
                VStack(alignment: .leading, spacing: 8) {
                    permissionRow("Enregistrement de l'écran", granted: screenRecording) {
                        CGRequestScreenCaptureAccess()
                        openSettings("Privacy_ScreenCapture")
                    }
                    permissionRow("Accessibilité (clavier et souris)", granted: accessibility) {
                        InputInjector.requestTrust()
                        openSettings("Privacy_Accessibility")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Quitter") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear { editedCode = server.passcode }
        .onReceive(timer) { _ in
            accessibility = InputInjector.isTrusted
            screenRecording = CGPreflightScreenCaptureAccess()
        }
    }

    private func permissionRow(_ title: String, granted: Bool, request: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(title)
            Spacer()
            if !granted {
                Button("Autoriser", action: request)
            }
        }
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
