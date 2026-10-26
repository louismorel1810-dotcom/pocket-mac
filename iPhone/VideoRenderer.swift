import AVFoundation
import CoreMedia
import UIKit

/// Affiche le flux H.264 du Mac, décodé par la puce de l'iPhone.
final class VideoRenderer {
    let layer = AVSampleBufferDisplayLayer()
    var onNeedKeyframe: (() -> Void)?

    private var format: CMVideoFormatDescription?
    private var waitingForKeyframe = true
    private var lastKeyframeRequest = Date.distantPast

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
    }

    func reset() {
        format = nil
        waitingForKeyframe = true
        DispatchQueue.main.async {
            self.layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        }
    }

    /// Reçoit les paramètres SPS/PPS envoyés avant chaque image clé.
    func setFormat(_ data: Data) {
        var r = ByteReader(data)
        guard let count = try? r.u8(), count > 0 else { return }
        var sets: [Data] = []
        for _ in 0..<count {
            guard let length = try? r.u16(), let set = try? r.bytes(Int(length)) else { return }
            sets.append(set)
        }

        let buffers = sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
            set.copyBytes(to: p, count: set.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        let pointers = buffers.map { UnsafePointer($0) }
        let sizes = sets.map { $0.count }

        var newFormat: CMFormatDescription?
        let status = pointers.withUnsafeBufferPointer { p in
            sizes.withUnsafeBufferPointer { s in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                                                                    parameterSetCount: sets.count,
                                                                    parameterSetPointers: p.baseAddress!,
                                                                    parameterSetSizes: s.baseAddress!,
                                                                    nalUnitHeaderLength: 4,
                                                                    formatDescriptionOut: &newFormat)
            }
        }
        guard status == noErr, let newFormat else { return }
        format = newFormat
    }

    /// Reçoit une image : [u8 image clé][données AVCC].
    func enqueue(_ data: Data) {
        guard data.count > 1 else { return }
        let isKey = data[data.startIndex] == 1
        if waitingForKeyframe {
            guard isKey else {
                requestKeyframe()
                return
            }
            waitingForKeyframe = false
        }
        guard let format else {
            requestKeyframe()
            return
        }

        let frame = data.dropFirst()
        let length = frame.count
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: length,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { return }
        let copied = frame.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: length)
        }
        guard copied == kCMBlockBufferNoErr else { return }

        var sample: CMSampleBuffer?
        var size = length
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                        sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size,
                                        sampleBufferOut: &sample) == noErr,
              let sample else { return }

        // Pas d'horloge : chaque image s'affiche dès qu'elle arrive, pour un retard minimal.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        DispatchQueue.main.async {
            let renderer = self.layer.sampleBufferRenderer
            if renderer.status == .failed {
                // Arrive après un passage en arrière-plan : on repart d'une image clé.
                renderer.flush()
                self.waitingForKeyframe = true
                self.requestKeyframe()
                return
            }
            renderer.enqueue(sample)
        }
    }

    /// Au plus une demande toutes les demi-secondes.
    private func requestKeyframe() {
        let now = Date()
        guard now.timeIntervalSince(lastKeyframeRequest) > 0.5 else { return }
        lastKeyframeRequest = now
        onNeedKeyframe?()
    }
}
