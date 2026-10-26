import Network
import SwiftUI

@main
struct PocketMacApp: App {
    @StateObject private var session = MacSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: MacSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.state == .idle {
                ConnectView()
            } else {
                SessionView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: session.pause()
            case .active: session.resume()
            default: break
            }
        }
    }
}

// MARK: - Recherche des Mac

/// Trouve tout seul les Mac du même Wi-Fi qui ont l'appli compagnon ouverte.
final class MacBrowser: ObservableObject {
    @Published private(set) var macs: [NWBrowser.Result] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: PocketMac.serviceType, domain: nil), using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.macs = results.sorted { Self.name(of: $0) < Self.name(of: $1) }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    static func name(of result: NWBrowser.Result) -> String {
        if case let .service(name, _, _, _) = result.endpoint {
            return name
        }
        return "\(result.endpoint)"
    }
}

// MARK: - Écran de connexion

struct ConnectView: View {
    @EnvironmentObject private var session: MacSession
    @StateObject private var browser = MacBrowser()
    @AppStorage(Pref.manualHost) private var manualHost = ""
    @AppStorage(Pref.quality) private var quality: Quality = .balanced
    @AppStorage(Pref.audio) private var audio = true

    @State private var pending: (endpoint: NWEndpoint, key: String)?
    @State private var passcode = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if browser.macs.isEmpty {
                        Label("Recherche des Mac sur ce Wi-Fi…", systemImage: "wifi")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(browser.macs, id: \.self) { result in
                        let name = MacBrowser.name(of: result)
                        Button {
                            ask(result.endpoint, key: name)
                        } label: {
                            Label(name, systemImage: "laptopcomputer")
                        }
                    }
                } header: {
                    Text("Mac à proximité")
                } footer: {
                    Text("Ouvrez l'appli « Pocket Mac Compagnon » sur le Mac à piloter.")
                }

                Section {
                    TextField("100.x.x.x ou nom-du-mac", text: $manualHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Se connecter") {
                        let host = manualHost.trimmingCharacters(in: .whitespaces)
                        ask(.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: PocketMac.port)!), key: host)
                    }
                    .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("À distance (hors de chez vous)")
                } footer: {
                    Text("Installez Tailscale sur l'iPhone et sur le Mac, avec le même compte, puis saisissez ici l'adresse 100.x.x.x affichée dans le menu de l'appli compagnon.")
                }

                if case let .failed(message) = session.state {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Pocket Mac")
            .toolbar {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert("Code du Mac", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                SecureField("Code affiché sur le Mac", text: $passcode)
                    .keyboardType(.numberPad)
                Button("Annuler", role: .cancel) { pending = nil }
                Button("Connexion") { connect() }
            } message: {
                Text("Le code est affiché dans le menu de l'appli compagnon, en haut de l'écran du Mac.")
            }
        }
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }

    private func ask(_ endpoint: NWEndpoint, key: String) {
        passcode = Keychain.passcode(for: key)
        pending = (endpoint, key)
    }

    private func connect() {
        guard let pending else { return }
        Keychain.setPasscode(passcode, for: pending.key)
        session.connect(to: pending.endpoint, passcode: passcode, settings: quality.settings(audio: audio))
        self.pending = nil
    }
}

// MARK: - Session : écran du Mac en haut, MacBook en bas

struct SessionView: View {
    @EnvironmentObject private var session: MacSession
    @AppStorage(Pref.theme) private var theme: Theme = .spaceGray
    @AppStorage(Pref.layout) private var layout: KeyboardLayout = .azerty
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    ScreenView(session: session, screen: session.screen)
                    statusOverlay
                    controls
                }
                .frame(height: geo.size.height * 0.5)

                VStack(spacing: 8) {
                    KeyboardView(session: session, layout: layout, theme: theme)
                        .frame(height: geo.size.height * 0.5 * 0.6)
                    TrackpadView(session: session)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.trackpad))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, geo.size.width * 0.18)
                }
                .padding(8)
                .frame(maxHeight: .infinity)
                .background(theme.deck)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(.keyboard)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    @ViewBuilder private var statusOverlay: some View {
        switch session.state {
        case .connecting:
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Connexion au Mac…").foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).multilineTextAlignment(.center).foregroundStyle(.white)
                Button("Réessayer") { session.reconnect() }.buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            EmptyView()
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            Button {
                session.disconnect()
            } label: {
                Image(systemName: "xmark")
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(6)
    }
}

// MARK: - Réglages

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.theme) private var theme: Theme = .spaceGray
    @AppStorage(Pref.layout) private var layout: KeyboardLayout = .azerty
    @AppStorage(Pref.quality) private var quality: Quality = .balanced
    @AppStorage(Pref.audio) private var audio = true
    @AppStorage(Pref.keySounds) private var keySounds = true
    @AppStorage(Pref.haptics) private var haptics = true
    @AppStorage(Pref.invertScroll) private var invertScroll = false
    @AppStorage(Pref.trackpadSpeed) private var trackpadSpeed = 2.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Apparence") {
                    Picker("Thème", selection: $theme) {
                        ForEach(Theme.allCases) { theme in
                            Label {
                                Text(theme.title)
                            } icon: {
                                Circle().fill(theme.deck).frame(width: 18, height: 18)
                            }
                            .tag(theme)
                        }
                    }
                    Picker("Clavier", selection: $layout) {
                        ForEach(KeyboardLayout.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Toggle("Son des touches", isOn: $keySounds)
                    Toggle("Vibrations", isOn: $haptics)
                } footer: {
                    Text("Le son des touches suit le réglage « Sons du clavier » de l'iPhone.")
                }
                Section("Trackpad") {
                    VStack(alignment: .leading) {
                        Text("Vitesse du pointeur")
                        Slider(value: $trackpadSpeed, in: 0.5...5)
                    }
                    Toggle("Inverser le défilement", isOn: $invertScroll)
                }
                Section {
                    Picker("Qualité", selection: $quality) {
                        ForEach(Quality.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Son du Mac sur l'iPhone", isOn: $audio)
                } header: {
                    Text("Image et son")
                } footer: {
                    Text("S'applique à la prochaine connexion.")
                }
                Section("Gestes") {
                    Text("Écran : toucher = clic à cet endroit, appui long = clic droit, pincer = zoomer, double toucher à deux doigts = dézoomer.")
                    Text("Trackpad : un doigt = pointeur, toucher = clic, toucher à deux doigts = clic droit, deux doigts = défiler, appui long puis glisser = déplacer un élément.")
                    Text("Trois doigts : gauche / droite = changer de bureau, haut = Mission Control, bas = fenêtres de l'app.")
                }
                .font(.footnote)
            }
            .navigationTitle("Réglages")
            .toolbar {
                Button("OK") { dismiss() }
            }
        }
    }
}
