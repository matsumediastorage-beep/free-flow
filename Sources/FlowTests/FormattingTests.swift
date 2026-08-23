import Foundation

@testable import FlowKit

/// Covers the cleanup that runs when there's no API key — which, for anyone who
/// hasn't set one up, is every dictation they will ever do.
@MainActor
func registerFormattingTests(_ suite: TestSuite) async {

    let context = FormattingContext(appName: nil, vocabulary: [])

    await suite.test("local cleanup strips standalone fillers") {
        let result = await LocalFormatter().format(
            "um so send me the uh file tomorrow", context: context)
        suite.expectEqual(result, "So send me the file tomorrow.")
    }

    await suite.test("local cleanup leaves meaningful words alone") {
        // "like" and "so" carry meaning often enough that removing them is
        // riskier than leaving them in.
        let result = await LocalFormatter().format(
            "it works like a charm", context: context)
        suite.expectEqual(result, "It works like a charm.")
    }

    await suite.test("local cleanup does not double up terminal punctuation") {
        let result = await LocalFormatter().format("is that ready?", context: context)
        suite.expectEqual(result, "Is that ready?")
    }

    await suite.test("local cleanup returns the original when it would empty it") {
        // A transcript of nothing but fillers must not paste an empty string.
        let result = await LocalFormatter().format("um uh hmm", context: context)
        suite.expect(!result.isEmpty, "filler-only input pasted nothing")
    }

    await suite.test("passthrough only trims") {
        let result = await PassthroughFormatter().format(
            "  um so like whatever  ", context: context)
        suite.expectEqual(result, "um so like whatever")
    }

    // MARK: - Latency budget

    await suite.test("cleanup budget scales with transcript length") {
        let short = ClaudeFormatter.timeout(forCharacterCount: 40)
        let long = ClaudeFormatter.timeout(forCharacterCount: 1_200)
        suite.expect(long > short, "a paragraph got the same budget as a sentence")
    }

    await suite.test("cleanup budget stays inside its floor and ceiling") {
        suite.expect(ClaudeFormatter.timeout(forCharacterCount: 0) >= 1.2)
        suite.expect(ClaudeFormatter.timeout(forCharacterCount: 100_000) <= 5.0)
    }

    await suite.test("on-device budget scales and stays bounded") {
        let short = AppleFormatter.timeout(forCharacterCount: 40)
        let long = AppleFormatter.timeout(forCharacterCount: 1_200)
        suite.expect(long > short)
        suite.expect(AppleFormatter.timeout(forCharacterCount: 100_000) <= 8.0)
        suite.expect(AppleFormatter.timeout(forCharacterCount: 0) >= 2.0, "floor too low for a cold start")
    }

    // MARK: - The on-device model, for real

    await suite.test("on-device cleanup actually cleans a transcript") {
        guard AppleFormatter.isAvailable else {
            print("      (skipped: \(AppleFormatter.unavailableReason ?? "unavailable"))")
            return
        }

        let raw = "um so like can you send me the uh the file tomorrow ok"
        let started = Date()
        // PassthroughFormatter as the fallback, so a silent failure shows up as
        // the unchanged input rather than being masked by rule-based cleanup.
        let result = await AppleFormatter(fallback: PassthroughFormatter())
            .format(raw, context: context)
        let elapsed = Date().timeIntervalSince(started)

        print("      in:  \(raw)")
        print("      out: \(result)")
        print("      \(String(format: "%.2f", elapsed))s")

        suite.expect(!result.isEmpty, "returned nothing")
        suite.expect(result != raw, "made no change at all — the model didn't run")
        suite.expect(
            !result.lowercased().contains(" um "), "left a filler word in")
    }

    await suite.test("on-device cleanup returns a dictated question, never an answer") {
        guard AppleFormatter.isAvailable else { return }

        // The safety property that matters most: dictating a question must type
        // the question, not Claude's or Apple's answer to it.
        let result = await AppleFormatter(fallback: PassthroughFormatter())
            .format("what is the capital of france", context: context)
        print("      out: \(result)")
        suite.expect(
            !result.lowercased().contains("paris"),
            "the model answered the question instead of transcribing it")
    }
}
