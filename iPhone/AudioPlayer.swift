import AVFoundation

/// Joue le son du Mac sur l'iPhone.
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    private let lock = NSLock()
    private var queued = 0
    private var attached = false

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        if !attached {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            attached = true
        }
        if !engine.isRunning {
            try? engine.start()
        }
        node.play()
    }

    func stop() {
        node.stop()
        engine.stop()
        lock.lock(); queued = 0; lock.unlock()
    }

    /// PCM Int16 stéréo entrelacé.
    func play(_ data: Data) {
        guard engine.isRunning else { return }
        let frames = data.count / 4
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            for i in 0..<frames {
                let l = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 4, as: Int16.self))
                let r = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 4 + 2, as: Int16.self))
                channels[0][i] = Float(l) / 32768
                channels[1][i] = Float(r) / 32768
            }
        }

        // Trop de son en attente = du retard : on jette plutôt que de décaler l'image et le son.
        lock.lock()
        guard queued < 8 else { lock.unlock(); return }
        queued += 1
        lock.unlock()
        node.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.queued = max(0, self.queued - 1); self.lock.unlock()
        }
    }
}
