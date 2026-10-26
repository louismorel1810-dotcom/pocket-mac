import CryptoKit
import Foundation
import Network
import Security

extension NWParameters {
    /// TCP + TLS à clé partagée : le code choisi sur le Mac sert à la fois de mot de passe
    /// et de clé de chiffrement. Sans le bon code, la connexion échoue.
    static func pocketMac(passcode: String) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10

        let tls = NWProtocolTLS.Options()
        let key = SymmetricKey(data: Data(passcode.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data("PocketMac".utf8), using: key)
        let psk = code.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("PocketMac".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,
                                                psk as __DispatchData,
                                                identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
                                                    tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256)!)

        let params = NWParameters(tls: tls, tcp: tcp)
        params.includePeerToPeer = true
        return params
    }
}

/// Connexion qui découpe le flux en messages [type][longueur][contenu].
final class FramedConnection {
    let connection: NWConnection
    var onMessage: ((MessageType, Data) -> Void)?
    var onStateChange: ((NWConnection.State) -> Void)?

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var _pendingBytes = 0

    /// Octets envoyés mais pas encore partis sur le réseau (pour éviter d'accumuler du retard).
    var pendingBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return _pendingBytes
    }

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    convenience init(endpoint: NWEndpoint, passcode: String, queue: DispatchQueue) {
        self.init(connection: NWConnection(to: endpoint, using: .pocketMac(passcode: passcode)), queue: queue)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.onStateChange?(state)
            if case .ready = state {
                self.receiveHeader()
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
    }

    func send(_ type: MessageType, _ payload: Data = Data()) {
        var w = ByteWriter()
        w.u8(type.rawValue)
        w.u32(UInt32(payload.count))
        w.bytes(payload)
        let count = w.data.count
        lock.lock(); _pendingBytes += count; lock.unlock()
        connection.send(content: w.data, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self._pendingBytes -= count; self.lock.unlock()
        })
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard error == nil, let data, data.count == 5 else {
                if error != nil || isComplete { self.connection.cancel() }
                return
            }
            var r = ByteReader(data)
            guard let type = try? r.u8(), let length = try? r.u32(), length < 64_000_000 else {
                self.connection.cancel()
                return
            }
            if length == 0 {
                self.deliver(type, Data())
                self.receiveHeader()
            } else {
                self.receivePayload(type: type, length: Int(length))
            }
        }
    }

    private func receivePayload(type: UInt8, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard error == nil, let data, data.count == length else {
                if error != nil || isComplete { self.connection.cancel() }
                return
            }
            self.deliver(type, data)
            self.receiveHeader()
        }
    }

    private func deliver(_ raw: UInt8, _ data: Data) {
        if let type = MessageType(rawValue: raw) {
            onMessage?(type, data)
        }
    }
}
