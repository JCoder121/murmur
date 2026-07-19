import XCTest
@testable import WisprCloneCore

final class WAVWriterTests: XCTestCase {
    func testWritesValidMono16kHeader() throws {
        let samples = [Float](repeating: 0.5, count: 16000) // 1s
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wavwriter-test.wav")
        try WAVWriter.write(samples: samples, sampleRate: 16000, to: url)
        let data = try Data(contentsOf: url)

        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        // fmt chunk: PCM(1), mono(1), 16000 Hz, 16-bit
        XCTAssertEqual(data[20], 1); XCTAssertEqual(data[22], 1)
        let rate = data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(rate, 16000)
        XCTAssertEqual(data[34], 16)
        // data chunk size = 16000 samples * 2 bytes
        let dataSize = data[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(dataSize, 32000)
        XCTAssertEqual(data.count, 44 + 32000)
    }

    func testClampsOutOfRangeSamples() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wavwriter-clamp.wav")
        try WAVWriter.write(samples: [2.0, -2.0], sampleRate: 16000, to: url)
        let data = try Data(contentsOf: url)
        let s0 = data[44..<46].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        let s1 = data[46..<48].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        XCTAssertEqual(s0, Int16.max)
        XCTAssertEqual(s1, Int16.min)
    }
}
