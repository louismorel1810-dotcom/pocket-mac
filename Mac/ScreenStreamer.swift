import CoreMedia
import Foundation
import ScreenCaptureKit
import VideoToolbox

enum StreamError: LocalizedError {
    case noDisplay
    case encoder(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "Aucun écran trouvé"
        case .encoder(let s): return "Encodeur vidéo indisponible (\(s))"
        }
    }
}

/// Filme l'écran principal (ScreenCaptureKit), l'encode en H.264 et récupère le son du Mac.
final class ScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate {
    var onVideoFormat: ((Data) -> Void)?
    var onVideoFrame: ((Data, Bool) -> Void)?
    var onAudio: ((Data) -> Void)?
    var onStop: ((Error?) -> Void)?

    private(set) var displayID: CGDirectDisplayID = CGMainDisplayID()

    private var stream: SCStream?
    private var encoder: VTCompressionSession?
    private var lastPixelBuffer: CVPixelBuffer?
    private var forceKey = true
    private let videoQueue = DispatchQueue(label: "pocketmac.video")
    private let audioQueue = DispatchQueue(label: "pocketmac.audio")

    func start(settings: StreamSettings) async throws -> ScreenInfo {
        await stop()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw StreamError.noDisplay
        }
        displayID = display.displayID

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let scale = Double(filter.pointPixelScale)
        var width = Int(Double(display.width) * scale)
        var height = Int(Double(display.height) * scale)
        if width > settings.maxWidth {
            height = height * settings.maxWidth / width
            width = settings.maxWidth
        }
        width &= ~1
        height &= ~1

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(settings.fps, 1)))
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.showsCursor = true
        config.queueDepth = 5
        config.capturesAudio = settings.audio
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true

        try videoQueue.sync {
            try makeEncoder(width: width, height: height, settings: settings)
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        if settings.audio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        try await stream.startCapture()
        self.stream = stream

        let name = Host.current().localizedName ?? "Mac"
        return ScreenInfo(name: name, width: width, height: height)
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        videoQueue.sync {
            if let encoder {
                VTCompressionSessionCompleteFrames(encoder, untilPresentationTimeStamp: .invalid)
                VTCompressionSessionInvalidate(encoder)
            }
            encoder = nil
            lastPixelBuffer = nil
        }
    }

    /// Demande une image clé. Si l'écran ne bouge pas, on réencode la dernière image
    /// pour que l'iPhone ait quelque chose à afficher tout de suite.
    func forceKeyframe() {
        videoQueue.async {
            self.forceKey = true
            if let pb = self.lastPixelBuffer {
                self.encode(pb)
            }
        }
    }

    // MARK: - Encodeur

    private func makeEncoder(width: Int, height: Int, settings: StreamSettings) throws {
        if let encoder {
            VTCompressionSessionInvalidate(encoder)
        }
        encoder = nil

        let spec = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true] as CFDictionary
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(allocator: nil,
                                                width: Int32(width),
                                                height: Int32(height),
                                                codecType: kCMVideoCodecType_H264,
                                                encoderSpecification: spec,
                                                imageBufferAttributes: nil,
                                                compressedDataAllocator: nil,
                                                outputCallback: nil,
                                                refcon: nil,
                                                compressionSessionOut: &session)
        guard status == noErr, let session else { throw StreamError.encoder(status) }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: settings.bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: settings.fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 4 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
        encoder = session
        forceKey = true
    }

    private func encode(_ pixelBuffer: CVPixelBuffer) {
        guard let encoder else { return }
        var props: CFDictionary?
        if forceKey {
            forceKey = false
            props = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        }
        let pts = CMClockGetTime(CMClockGetHostTimeClock())
        VTCompressionSessionEncodeFrame(encoder,
                                        imageBuffer: pixelBuffer,
                                        presentationTimeStamp: pts,
                                        duration: .invalid,
                                        frameProperties: props,
                                        infoFlagsOut: nil) { [weak self] status, _, sample in
            guard status == noErr, let sample, let self else { return }
            self.handleEncoded(sample)
        }
    }

    private func handleEncoded(_ sample: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let notSync = (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
        let isKey = !notSync

        if isKey, let format = sample.formatDescription {
            onVideoFormat?(parameterSets(of: format))
        }

        guard let block = sample.dataBuffer else { return }
        let length = CMBlockBufferGetDataLength(block)
        var payload = Data(count: length + 1)
        payload[0] = isKey ? 1 : 0
        let status = payload.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress! + 1)
        }
        guard status == kCMBlockBufferNoErr else { return }
        onVideoFrame?(payload, isKey)
    }

    private func parameterSets(of format: CMFormatDescription) -> Data {
        var count = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0,
                                                           parameterSetPointerOut: nil, parameterSetSizeOut: nil,
                                                           parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        var w = ByteWriter()
        w.u8(UInt8(count))
        for i in 0..<count {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: i,
                                                               parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
                                                               parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            if let pointer {
                w.u16(UInt16(size))
                w.bytes(Data(bytes: pointer, count: size))
            }
        }
        return w.data
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            handleScreen(sampleBuffer)
        case .audio:
            handleAudio(sampleBuffer)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }

    private func handleScreen(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        lastPixelBuffer = pixelBuffer
        encode(pixelBuffer)
    }

    /// Convertit le son (Float32) en Int16 stéréo entrelacé, deux fois plus léger à envoyer.
    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let format = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mBitsPerChannel == 32 else { return }

        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        let channels = Int(asbd.mChannelsPerFrame)
        let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard frames > 0, channels > 0 else { return }

        var out = Data(count: frames * 4)
        do {
            try sampleBuffer.withAudioBufferList { buffers, _ in
                out.withUnsafeMutableBytes { raw in
                    let dst = raw.bindMemory(to: Int16.self)
                    for frame in 0..<frames {
                        for ch in 0..<2 {
                            let src = min(ch, channels - 1)
                            let value: Float
                            if nonInterleaved {
                                guard src < buffers.count, let p = buffers[src].mData else { return }
                                value = p.assumingMemoryBound(to: Float.self)[frame]
                            } else {
                                guard let p = buffers[0].mData else { return }
                                value = p.assumingMemoryBound(to: Float.self)[frame * channels + src]
                            }
                            dst[frame * 2 + ch] = Int16(max(-1, min(1, value)) * 32767).littleEndian
                        }
                    }
                }
            }
        } catch {
            return
        }
        onAudio?(out)
    }
}
