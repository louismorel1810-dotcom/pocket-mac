import Network
import SwiftUI

/// Connexion avec un Mac : reçoit l'image et le son, envoie clavier, souris et gestes.
final class MacSession: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var screen: ScreenInfo?

    let video = VideoRenderer()
    let audio = AudioPlayer()

    private var connection: FramedConnection?
    private var target: (endpoint: NWEndpoint, passcode: String, settings: StreamSettings)?
    private let queue = DispatchQueue(label: "pocketmac.client")
    private var paused = false

    init() {
        video.onNeedKeyframe = { [weak self] in
            self?.connection?.send(.requestKeyframe)
        }
    }

    func connect(to endpoint: NWEndpoint, passcode: String, settings: StreamSettings) {
        target = (endpoint, passcode, settings)
        reconnect()
    }

    func reconnect() {
        guard let target else { return }
        paused = false
        connection?.cancel()
        state = .connecting
        video.reset()
        if target.settings.audio {
            audio.start()
        }

        let connection = FramedConnection(endpoint: target.endpoint, passcode: target.passcode, queue: queue)
        self.connection = connection
        connection.onStateChange = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                if let json = try? JSONEncoder().encode(target.settings) {
                    connection.send(.settings, json)
                }
                self.setState(.connected, for: connection)
            case .waiting(let error):
                self.setState(.failed(Self.message(for: error)), for: connection)
            case .failed(let error):
                self.setState(.failed(Self.message(for: error)), for: connection)
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.onMessage = { [weak self] type, data in
            self?.handle(type, data)
        }
        connection.start()
    }

    func disconnect() {
        target = nil
        connection?.cancel()
        connection = nil
        audio.stop()
        state = .idle
        screen = nil
    }

    /// L'appli passe en arrière-plan : on coupe, on se reconnecte au retour.
    func pause() {
        guard target != nil else { return }
        paused = true
        connection?.cancel()
        connection = nil
        audio.stop()
    }

    func resume() {
        guard paused else { return }
        reconnect()
    }

    private func setState(_ state: State, for connection: FramedConnection) {
        DispatchQueue.main.async {
            guard self.connection === connection else { return }
            self.state = state
        }
    }

    private static func message(for error: NWError) -> String {
        switch error {
        case .tls:
            return "Code incorrect. Vérifiez le code affiché sur le Mac."
        case .posix(let code) where code == .ECONNREFUSED:
            return "Le Mac refuse la connexion. L'appli Pocket Mac Compagnon est-elle ouverte ?"
        default:
            return "Mac injoignable (\(error.localizedDescription)). À distance, vérifiez que Tailscale est actif sur les deux appareils."
        }
    }

    private func handle(_ type: MessageType, _ data: Data) {
        switch type {
        case .hello:
            if let info = try? JSONDecoder().decode(ScreenInfo.self, from: data) {
                DispatchQueue.main.async { self.screen = info }
            }
        case .videoFormat:
            video.setFormat(data)
        case .videoFrame:
            video.enqueue(data)
        case .audio:
            audio.play(data)
        default:
            break
        }
    }

    // MARK: - Commandes envoyées au Mac

    func key(_ code: UInt16, down: Bool, flags: ModifierFlags) {
        var w = ByteWriter()
        w.u16(code)
        w.u8(down ? 1 : 0)
        w.u64(flags.rawValue)
        connection?.send(.key, w.data)
    }

    func tapKey(_ code: UInt16, flags: ModifierFlags = []) {
        key(code, down: true, flags: flags)
        key(code, down: false, flags: flags)
    }

    func moveBy(dx: CGFloat, dy: CGFloat) {
        var w = ByteWriter()
        w.f32(Float(dx))
        w.f32(Float(dy))
        connection?.send(.mouseMove, w.data)
    }

    func moveTo(x: CGFloat, y: CGFloat) {
        var w = ByteWriter()
        w.f32(Float(min(max(x, 0), 1)))
        w.f32(Float(min(max(y, 0), 1)))
        connection?.send(.mouseTo, w.data)
    }

    func button(_ button: UInt8, down: Bool) {
        var w = ByteWriter()
        w.u8(button)
        w.u8(down ? 1 : 0)
        connection?.send(.mouseButton, w.data)
    }

    func click(_ button: UInt8 = 0) {
        self.button(button, down: true)
        self.button(button, down: false)
    }

    func scroll(dx: CGFloat, dy: CGFloat) {
        var w = ByteWriter()
        w.f32(Float(dx))
        w.f32(Float(dy))
        connection?.send(.scroll, w.data)
    }

    func perform(_ action: MacAction) {
        var w = ByteWriter()
        w.u8(action.rawValue)
        connection?.send(.action, w.data)
    }
}
