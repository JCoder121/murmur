import AVFoundation

public final class Recorder {
    public var levelHandler: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private static let maxSamples = 16000 * 120  // 2 min cap

    public init() {}

    public static func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { NSLog("Recorder: microphone permission denied") }
        }
    }

    public func start() throws {
        lock.lock(); samples = []; lock.unlock()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: "Recorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "audio format setup failed"])
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.consume(buffer, converter: converter, outFormat: outFormat)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outFormat: AVAudioFormat) {
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, let ch = out.floatChannelData else { return }
        let n = Int(out.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: ch[0], count: n))

        lock.lock()
        if samples.count < Self.maxSamples { samples.append(contentsOf: chunk) }
        lock.unlock()

        if n > 0 {
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(n))
            levelHandler?(min(1, rms * 8))
        }
    }

    public func stop() throws -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        lock.lock(); let captured = samples; samples = []; lock.unlock()
        guard captured.count > 8000 else { return nil }  // < 0.5s: discard
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wispr-\(UUID().uuidString).wav")
        try WAVWriter.write(samples: captured, sampleRate: 16000, to: url)
        return url
    }
}
