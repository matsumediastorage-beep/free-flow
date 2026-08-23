import Foundation

/// A ~60-line stand-in for swift-testing.
///
/// It exists because Xcode's Command Line Tools ship neither a usable
/// swift-testing nor XCTest, so `swift test` cannot run without a full Xcode
/// install. The logic these tests cover — whether a keystroke is dictation or a
/// capital letter — is the most breakable code in the app, so it needs a check
/// that runs on any Mac with `swift run FlowTests`, not one that needs 10GB of
/// developer tools first.
///
/// Deliberately tiny: no discovery, no parallelism, no fixtures. Tests are
/// registered by calling `suite.test(...)` from `main.swift`.
@MainActor
final class TestSuite {

    private var failuresInCurrentTest: [String] = []
    private(set) var passed = 0
    private(set) var failedNames: [String] = []

    // MARK: - Running

    func test(_ name: String, _ body: () async throws -> Void) async {
        failuresInCurrentTest = []
        do {
            try await body()
        } catch {
            failuresInCurrentTest.append("threw an unexpected error: \(error)")
        }

        if failuresInCurrentTest.isEmpty {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failedNames.append(name)
            print("  ✗ \(name)")
            for failure in failuresInCurrentTest {
                print("      \(failure)")
            }
        }
    }

    /// Prints the summary and returns the process exit code.
    func summarize() -> Int32 {
        let total = passed + failedNames.count
        print("")
        if failedNames.isEmpty {
            print("\(passed)/\(total) tests passed.")
            return 0
        }
        print("\(passed)/\(total) passed — \(failedNames.count) FAILED:")
        for name in failedNames { print("  · \(name)") }
        return 1
    }

    // MARK: - Expectations

    func expect(
        _ condition: Bool,
        _ description: @autoclosure () -> String = "",
        line: UInt = #line
    ) {
        guard !condition else { return }
        let detail = description()
        failuresInCurrentTest.append(
            "line \(line): expectation failed" + (detail.isEmpty ? "" : " — \(detail)"))
    }

    func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ description: @autoclosure () -> String = "",
        line: UInt = #line
    ) {
        guard actual != expected else { return }
        let detail = description()
        failuresInCurrentTest.append(
            "line \(line): expected \(expected), got \(actual)"
                + (detail.isEmpty ? "" : " — \(detail)"))
    }
}
