import Foundation

/// Pre-upload guard for track media. Port of the web's `lib/media-validate.ts`
/// sniffing (keep the two in step).
///
/// YouTube-to-MP3 sites hand out YouTube's DASH audio stream (fragmented MP4)
/// renamed to `.mp3`. The upload path picks the content type from the
/// extension, storage serves it as audio/mpeg, and iOS / Safari refuse to
/// play it. So the container is identified from its first bytes, never the
/// name.
public enum MediaSniffer {
    public enum Container: String {
        case mp3, wav, aiff, flac, ogg, webm, mp4, unknown
    }

    public struct ValidationError: Error, LocalizedError {
        public let reason: String
        public var errorDescription: String? { reason }
    }

    /// Throws a `ValidationError` with user-facing copy when the file
    /// shouldn't be uploaded as a track's streamable media.
    public static func validate(_ data: Data, fileName: String) throws {
        let head = [UInt8](data.prefix(4 * 1024 * 1024))
        let container = sniff(head)

        if container == .mp4 && isFragmentedMP4(head) {
            throw ValidationError(reason: "This file is in a streaming format that won't play on iPhones. Export it again as an MP3 or WAV from your audio app.")
        }
        if fileName.lowercased().hasSuffix(".mp3") && container != .mp3 {
            throw ValidationError(reason: "This file is named .mp3 but isn't actually an MP3. Export it again as an MP3 or WAV from your audio app.")
        }
    }

    /// `validate` for a file on disk — reads only the head it needs.
    public static func validate(fileAt url: URL, fileName: String) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
        try validate(head, fileName: fileName)
    }

    /// Identifies the container from its magic bytes.
    static func sniff(_ b: [UInt8]) -> Container {
        if ascii(b, 0, 3) == "ID3" {
            // ID3v2 tag: 10-byte header + syncsafe size, then the first audio
            // frame. If the frame lies past the bytes we read, trust the tag.
            guard b.count >= 10 else { return .unknown }
            let tagSize = (Int(b[6] & 0x7f) << 21) | (Int(b[7] & 0x7f) << 14)
                | (Int(b[8] & 0x7f) << 7) | Int(b[9] & 0x7f)
            let frame = 10 + tagSize
            return frame + 2 > b.count || isMpegAudioFrame(b, frame) ? .mp3 : .unknown
        }
        if isMpegAudioFrame(b, 0) { return .mp3 }
        if ascii(b, 0, 4) == "RIFF" && ascii(b, 8, 4) == "WAVE" { return .wav }
        if ascii(b, 0, 4) == "FORM" && ["AIFF", "AIFC"].contains(ascii(b, 8, 4)) { return .aiff }
        if ascii(b, 0, 4) == "fLaC" { return .flac }
        if ascii(b, 0, 4) == "OggS" { return .ogg }
        if b.count >= 4 && b[0] == 0x1a && b[1] == 0x45 && b[2] == 0xdf && b[3] == 0xa3 { return .webm }
        if ascii(b, 4, 4) == "ftyp" { return .mp4 }
        return .unknown
    }

    /// Fragmented MP4 (DASH / CMAF): `dash` major brand, a top-level `moof`,
    /// or an `mvex` inside `moov`.
    static func isFragmentedMP4(_ b: [UInt8]) -> Bool {
        if ascii(b, 8, 4) == "dash" { return true }
        if findBox(b, from: 0, to: b.count, type: "moof") != nil { return true }
        guard let moov = findBox(b, from: 0, to: b.count, type: "moov") else { return false }
        return findBox(b, from: moov.dataStart, to: moov.end, type: "mvex") != nil
    }

    // MARK: - Byte helpers

    /// MPEG audio frame header: 11 sync bits, then a non-reserved layer. ADTS
    /// AAC shares the sync word but uses layer 00, so it isn't taken for MP3.
    private static func isMpegAudioFrame(_ b: [UInt8], _ offset: Int) -> Bool {
        guard offset + 2 <= b.count else { return false }
        return b[offset] == 0xff && (b[offset + 1] & 0xe0) == 0xe0 && (b[offset + 1] & 0x06) != 0
    }

    private static func ascii(_ b: [UInt8], _ offset: Int, _ length: Int) -> String {
        guard offset + length <= b.count else { return "" }
        return String(decoding: b[offset..<offset + length], as: UTF8.self)
    }

    private static func uint32(_ b: [UInt8], _ offset: Int) -> Int {
        (Int(b[offset]) << 24) | (Int(b[offset + 1]) << 16) | (Int(b[offset + 2]) << 8) | Int(b[offset + 3])
    }

    /// Walks sibling MP4 boxes in `[from, to)` looking for `type`.
    private static func findBox(_ b: [UInt8], from: Int, to: Int, type: String) -> (dataStart: Int, end: Int)? {
        var offset = from
        let limit = min(to, b.count)
        while offset + 8 <= limit {
            var size = uint32(b, offset)
            var dataStart = offset + 8
            if size == 1 {
                guard offset + 16 <= b.count else { return nil }
                size = (uint32(b, offset + 8) << 32) | uint32(b, offset + 12)
                dataStart = offset + 16
            } else if size == 0 {
                size = b.count - offset
            }
            guard size >= 8, size <= Int.max - offset else { return nil }
            if ascii(b, offset + 4, 4) == type { return (dataStart, offset + size) }
            offset += size
        }
        return nil
    }
}
