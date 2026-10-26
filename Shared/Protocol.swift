import Foundation

/// Constantes partagées entre l'appli iPhone et l'appli compagnon du Mac.
enum PocketMac {
    static let serviceType = "_pocketmac._tcp"
    static let port: UInt16 = 7845
}

/// Chaque message = [type: u8][longueur: u32][contenu], entiers en big-endian.
enum MessageType: UInt8 {
    // Mac -> iPhone
    case hello = 1          // JSON ScreenInfo
    case videoFormat = 2    // [u8 nombre]([u16 longueur][SPS/PPS])*
    case videoFrame = 3     // [u8 image clé][H.264 AVCC]
    case audio = 4          // PCM Int16 stéréo entrelacé, 48 kHz, little-endian

    // iPhone -> Mac
    case settings = 20      // JSON StreamSettings
    case key = 21           // [u16 code touche Mac][u8 appuyé][u64 modificateurs]
    case mouseMove = 22     // [f32 dx][f32 dy]
    case mouseButton = 23   // [u8 bouton 0 = gauche, 1 = droit][u8 appuyé]
    case scroll = 24        // [f32 dx][f32 dy]
    case mouseTo = 25       // [f32 x][f32 y] normalisés 0...1
    case action = 26        // [u8 MacAction]
    case requestKeyframe = 27
}

struct ScreenInfo: Codable {
    var name: String
    var width: Int
    var height: Int
}

struct StreamSettings: Codable {
    var maxWidth: Int
    var fps: Int
    var bitrate: Int
    var audio: Bool
}

enum MacAction: UInt8, CaseIterable {
    case missionControl, appExpose, desktopLeft, desktopRight, showDesktop, launchpad
    case volumeUp, volumeDown, mute, playPause, nextTrack, previousTrack
    case brightnessUp, brightnessDown
}

/// Mêmes valeurs que CGEventFlags côté Mac.
struct ModifierFlags: OptionSet, Hashable {
    let rawValue: UInt64
    static let shift = ModifierFlags(rawValue: 1 << 17)
    static let control = ModifierFlags(rawValue: 1 << 18)
    static let option = ModifierFlags(rawValue: 1 << 19)
    static let command = ModifierFlags(rawValue: 1 << 20)
}

enum ProtocolError: Error {
    case truncated
}

struct ByteWriter {
    private(set) var data = Data()

    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) { append(v) }
    mutating func u32(_ v: UInt32) { append(v) }
    mutating func u64(_ v: UInt64) { append(v) }
    mutating func f32(_ v: Float) { append(v.bitPattern) }
    mutating func bytes(_ d: Data) { data.append(d) }

    private mutating func append<T: FixedWidthInteger>(_ v: T) {
        var big = v.bigEndian
        withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }
}

struct ByteReader {
    let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    var remaining: Int { data.endIndex - offset }

    mutating func u8() throws -> UInt8 { try uint(UInt8.self) }
    mutating func u16() throws -> UInt16 { try uint(UInt16.self) }
    mutating func u32() throws -> UInt32 { try uint(UInt32.self) }
    mutating func u64() throws -> UInt64 { try uint(UInt64.self) }
    mutating func f32() throws -> Float { Float(bitPattern: try u32()) }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count <= remaining else { throw ProtocolError.truncated }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func rest() -> Data {
        defer { offset = data.endIndex }
        return data.subdata(in: offset..<data.endIndex)
    }

    private mutating func uint<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard size <= remaining else { throw ProtocolError.truncated }
        var value: T = 0
        for i in 0..<size {
            value = (value << 8) | T(data[offset + i])
        }
        offset += size
        return value
    }
}
