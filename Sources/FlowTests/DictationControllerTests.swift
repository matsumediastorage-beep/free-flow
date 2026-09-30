import Foundation
@testable import FlowKit

@MainActor
private final class SlowRecorder: AudioRecording {
    var onLevel: (@Sendable (Float) -> Void)?
    var starts = 0
    var finishes = 0
    var cancels = 0
    var pending: [CheckedContinuation<Void, Error>] = []
    func prewarm() async throws {}
    func beginCapture() async throws {
        starts += 1
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func completeStart(failing: Bool = false) {
        let continuation = pending.removeFirst()
        if failing { continuation.resume(throwing: AudioError.noInputDevice) }
        else { continuation.resume() }
    }
    func finish() async -> [Float] {
        finishes += 1
        return [Float](repeating: 0, count: 8000)
    }
    func cancel() { cancels += 1 }
}

private actor TestEngine: TranscriptionEngine {
    var isReady = false
    var loadSeconds: Double = 0
    var warmupSeconds: Double = 0
    var preparing = false
    var pending: CheckedContinuation<Void, Never>?
    var progress: (@Sendable (PreparePhase) -> Void)?
    var transcriptions = 0
    func prepare(progress: @escaping @Sendable (PreparePhase) -> Void) async throws {
        self.progress = progress
        preparing = true
        await withCheckedContinuation { pending = $0 }
        isReady = true
    }
    func finishLoading() { pending?.resume(); pending = nil }
    func reportProgress() { progress?(.warming) }
    func setReady() { isReady = true }
    func transcribe(_ samples: [Float]) async throws -> Transcript {
        guard isReady else { throw TranscriptionError.notReady }
        transcriptions += 1
        return Transcript(text: "Test speech.", processingTime: 0.01)
    }
}

@MainActor
private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return false
}

@MainActor
private func makeController(_ recorder: SlowRecorder, _ engine: TestEngine) -> DictationController {
    let defaults = UserDefaults(suiteName: "FlowTests.\(UUID())")!
    let settings = Settings(defaults: defaults)
    settings.playSounds = false
    let history = HistoryStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("FlowTests-\(UUID()).json"))
    return DictationController(settings: settings, history: history, engine: engine,
        formatter: PassthroughFormatter(), recorder: recorder, insertText: { _ in })
}

@MainActor
func registerDictationTests(_ suite: TestSuite) async {
    await suite.test("slow microphone shows starting immediately and release waits for captured audio") {
        let recorder = SlowRecorder(), engine = TestEngine()
        await engine.setReady()
        let c = makeController(recorder, engine)
        c.handle(.armed)
        c.handle(.startedRecording)
        suite.expectEqual(c.state, .starting)
        suite.expect(await eventually { recorder.starts == 1 })
        c.handle(.stoppedRecording)
        suite.expectEqual(c.state, .transcribing)
        suite.expectEqual(recorder.finishes, 0)
        recorder.completeStart()
        suite.expect(await eventually { c.state == .finished("Test speech.") })
        suite.expectEqual(recorder.finishes, 1)
        c.stop()
    }

    await suite.test("cancelled slow startup cannot resurrect recording or overwrite the next session") {
        let recorder = SlowRecorder(), engine = TestEngine()
        let c = makeController(recorder, engine)
        c.handle(.armed); c.handle(.startedRecording)
        suite.expect(await eventually { recorder.starts == 1 })
        c.handle(.cancelled)
        suite.expectEqual(c.state, .idle)
        c.handle(.armed); c.handle(.startedRecording)
        suite.expect(await eventually { recorder.starts == 2 })
        recorder.completeStart()
        try? await Task.sleep(for: .milliseconds(20))
        suite.expectEqual(c.state, .starting)
        recorder.completeStart()
        suite.expect(await eventually { c.state == .listening })
        suite.expectEqual(recorder.finishes, 0)
        c.stop()
    }

    await suite.test("model progress and completion preserve an active recording") {
        let recorder = SlowRecorder(), engine = TestEngine()
        let c = makeController(recorder, engine)
        c.prepareEngine()
        suite.expectEqual(c.state, .preparing(.loading(0)))
        suite.expect(await eventually { await engine.preparing })
        c.handle(.armed); c.handle(.startedRecording)
        suite.expect(await eventually { recorder.starts == 1 })
        recorder.completeStart()
        suite.expect(await eventually { c.state == .listening })
        await engine.reportProgress()
        await engine.finishLoading()
        suite.expect(await eventually { await engine.isReady })
        try? await Task.sleep(for: .milliseconds(20))
        suite.expectEqual(c.state, .listening)
        // Even a late queued progress callback must be ignored after readiness.
        await engine.reportProgress()
        try? await Task.sleep(for: .milliseconds(20))
        suite.expectEqual(c.state, .listening)
        c.stop()
    }

    await suite.test("busy transcription ignores extra gestures and resumes after model loading") {
        let recorder = SlowRecorder(), engine = TestEngine()
        let c = makeController(recorder, engine)
        c.prepareEngine()
        suite.expect(await eventually { await engine.preparing })
        c.handle(.armed); c.handle(.startedRecording)
        suite.expect(await eventually { recorder.starts == 1 })
        recorder.completeStart()
        suite.expect(await eventually { c.state == .listening })
        c.handle(.stoppedRecording)
        suite.expect(await eventually { recorder.finishes == 1 })
        c.handle(.armed); c.handle(.startedRecording); c.handle(.cancelled)
        suite.expectEqual(recorder.starts, 1)
        suite.expectEqual(c.state, .transcribing)
        await engine.finishLoading()
        suite.expect(await eventually { c.state == .finished("Test speech.") })
        c.handle(.armed); c.handle(.startedRecording)
        suite.expect(await eventually { recorder.starts == 2 })
        recorder.completeStart()
        suite.expect(await eventually { c.state == .listening })
        try? await Task.sleep(for: .milliseconds(950))
        suite.expectEqual(c.state, .listening)
        c.stop()
    }

    await suite.test("microphone failure during an early release recovers for the next hold") {
        let recorder = SlowRecorder(), engine = TestEngine()
        await engine.setReady()
        let c = makeController(recorder, engine)
        c.handle(.armed); c.handle(.startedRecording)
        suite.expect(await eventually { recorder.starts == 1 })
        c.handle(.stoppedRecording)
        recorder.completeStart(failing: true)
        suite.expect(await eventually { c.state == .failed("No microphone available.") })
        try? await Task.sleep(for: .milliseconds(20))
        c.handle(.armed); c.handle(.startedRecording)
        suite.expect(await eventually { recorder.starts == 2 })
        recorder.completeStart()
        suite.expect(await eventually { c.state == .listening })
        c.stop()
    }

    await suite.test("stop while waiting for model cannot paste or transcribe later") {
        let recorder = SlowRecorder(), engine = TestEngine()
        let c = makeController(recorder, engine)
        c.prepareEngine()
        suite.expect(await eventually { await engine.preparing })
        c.handle(.armed); c.handle(.startedRecording)
        suite.expect(await eventually { recorder.starts == 1 })
        recorder.completeStart()
        suite.expect(await eventually { c.state == .listening })
        c.handle(.stoppedRecording)
        suite.expect(await eventually { recorder.finishes == 1 })
        c.stop()
        await engine.finishLoading()
        suite.expect(await eventually { await engine.isReady })
        try? await Task.sleep(for: .milliseconds(20))
        suite.expectEqual(await engine.transcriptions, 0)
        suite.expectEqual(c.state, .idle)
    }
}
