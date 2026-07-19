import Foundation

public enum WAVWriter {
    public static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        let dataSize = samples.count * 2
        var d = Data(capacity: 44 + dataSize)

        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }

        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + dataSize))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1)                          // PCM
        u16(1)                          // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))     // byte rate
        u16(2)                          // block align
        u16(16)                         // bits per sample
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(dataSize))

        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            let i: Int16 = clamped <= -1.0 ? .min : Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: i.littleEndian) { d.append(contentsOf: $0) }
        }
        try d.write(to: url)
    }
}
