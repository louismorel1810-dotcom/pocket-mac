import AppKit
import Foundation
import IOKit.pwr_mgt
import Network

/// Attend la connexion de l'iPhone, lui envoie l'écran et le son, et applique ses commandes.
final class Server: ObservableObject {
    @Published private(set) var status = "Démarrage…"
    @Published private(set) var connectedClient: String?
    @Published var passcode: String {
        didSet {
            UserDefaults.standard.set(passcode, forKey: "passcode")
            start()
        }
    }

    private let queue = DispatchQueue(label: "pocketmac.server")
    private let streamer = ScreenStreamer()
    private let input = InputInjector()
    private var listener: NWListener?
    private let clientLock = NSLock()
    private var _client: FramedConnection?
    /// Lu depuis plusieurs files (réseau, vidéo, son), d'où le verrou.
    private var client: FramedConnection? {
        get { clientLock.lock(); defer { clientLock.unlock() }; return _client }
        set { clientLock.lock(); _client = newValue; clientLock.unlock() }
    }
    private var waitingForKeyframe = false
    private var systemAwake: IOPMAssertionID = 0
    private var displayAwake: IOPMAssertionID = 0

    init() {
        passcode = UserDefaults.standard.string(forKey: "passcode") ?? Server.randomPasscode()
        UserDefaults.standard.set(passcode, forKey: "passcode")
        setupStreamer()
        start()
        // Le Mac ne se met jamais en veille tant que l'appli tourne.
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Pocket Mac attend l'iPhone" as CFString,
                                    &systemAwake)
    }

    static func randomPasscode() -> String {
        String((0..<6).map { _ in "0123456789".randomElement()! })
    }

    func start() {
        listener?.cancel()
        listener = nil
        guard passcode.count >= 4 else {
            setStatus("Choisissez un code d'au moins 4 caractères")
            return
        }
        do {
            let listener = try NWListener(using: .pocketMac(passcode: passcode),
                                          on: NWEndpoint.Port(rawValue: PocketMac.port)!)
            listener.service = NWListener.Service(name: Host.current().localizedName, type: PocketMac.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.setStatus("Prêt, en attente de l'iPhone")
                case .failed(let error): self?.setStatus("Erreur réseau : \(error.localizedDescription)")
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            setStatus("Erreur réseau : \(error.localizedDescription)")
        }
    }

    // MARK: - Connexion

    private func accept(_ connection: NWConnection) {
        // Un seul iPhone à la fois : le nouveau remplace l'ancien.
        client?.cancel()
        let client = FramedConnection(connection: connection, queue: queue)
        self.client = client

        client.onStateChange = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .ready:
                self.setConnected(Self.describe(connection.endpoint))
            case .failed, .cancelled:
                guard self.client === client else { return }
                self.client = nil
                self.setConnected(nil)
                Task { await self.streamer.stop() }
            default:
                break
            }
        }
        client.onMessage = { [weak self, weak client] type, data in
            guard let self, let client, self.client === client else { return }
            self.handle(type, data, from: client)
        }
        client.start()
    }

    private func handle(_ type: MessageType, _ data: Data, from client: FramedConnection) {
        var r = ByteReader(data)
        let display = streamer.displayID
        do {
            switch type {
            case .settings:
                let settings = try JSONDecoder().decode(StreamSettings.self, from: data)
                startStreaming(settings, to: client)
            case .key:
                let code = try r.u16()
                let down = try r.u8() != 0
                let flags = try r.u64()
                input.key(code, down: down, flags: flags)
            case .mouseMove:
                let dx = try r.f32()
                let dy = try r.f32()
                input.moveBy(dx: CGFloat(dx), dy: CGFloat(dy), display: display)
            case .mouseButton:
                let button = try r.u8()
                let down = try r.u8() != 0
                input.button(button, down: down)
            case .scroll:
                let dx = try r.f32()
                let dy = try r.f32()
                input.scroll(dx: CGFloat(dx), dy: CGFloat(dy))
            case .mouseTo:
                let x = try r.f32()
                let y = try r.f32()
                input.moveTo(x: CGFloat(x), y: CGFloat(y), display: display)
            case .action:
                if let action = MacAction(rawValue: try r.u8()) {
                    DispatchQueue.main.async { self.input.perform(action) }
                }
            case .requestKeyframe:
                streamer.forceKeyframe()
            case .hello, .videoFormat, .videoFrame, .audio:
                break
            }
        } catch {
            // Message incomplet : ignoré.
        }
    }

    private func startStreaming(_ settings: StreamSettings, to client: FramedConnection) {
        Task {
            do {
                let info = try await streamer.start(settings: settings)
                client.send(.hello, try JSONEncoder().encode(info))
            } catch {
                setStatus("Capture d'écran impossible : vérifiez l'autorisation « Enregistrement de l'écran »")
                client.cancel()
            }
        }
    }

    private func setupStreamer() {
        streamer.onVideoFormat = { [weak self] data in
            self?.client?.send(.videoFormat, data)
        }
        streamer.onVideoFrame = { [weak self] data, isKey in
            guard let self, let client = self.client else { return }
            // Réseau saturé (souvent à distance) : on saute des images plutôt que d'accumuler du retard,
            // puis on repart d'une image clé.
            if client.pendingBytes > 1_500_000 {
                self.waitingForKeyframe = true
                return
            }
            if self.waitingForKeyframe {
                guard isKey else {
                    self.streamer.forceKeyframe()
                    return
                }
                self.waitingForKeyframe = false
            }
            client.send(.videoFrame, data)
        }
        streamer.onAudio = { [weak self] data in
            guard let client = self?.client, client.pendingBytes < 1_000_000 else { return }
            client.send(.audio, data)
        }
        streamer.onStop = { [weak self] _ in
            self?.client?.cancel()
        }
    }

    // MARK: - État affiché dans le menu

    private func setStatus(_ text: String) {
        DispatchQueue.main.async { self.status = text }
    }

    private func setConnected(_ name: String?) {
        DispatchQueue.main.async {
            self.connectedClient = name
            self.status = name == nil ? "Prêt, en attente de l'iPhone" : "iPhone connecté"
            // Écran allumé tant que l'iPhone regarde.
            if name != nil, self.displayAwake == 0 {
                IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "Pocket Mac : iPhone connecté" as CFString,
                                            &self.displayAwake)
            } else if name == nil, self.displayAwake != 0 {
                IOPMAssertionRelease(self.displayAwake)
                self.displayAwake = 0
            }
        }
    }

    private static func describe(_ endpoint: NWEndpoint) -> String {
        if case let .hostPort(host, _) = endpoint {
            return "\(host)"
        }
        return "iPhone"
    }

    /// Adresses IPv4 du Mac (réseau local et Tailscale en 100.x.x.x).
    static func addresses() -> [String] {
        var result: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        return Array(Set(result)).sorted()
    }
}
