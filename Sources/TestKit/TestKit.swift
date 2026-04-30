import Foundation

public struct TestRunner {
    public static var passCount = 0
    public static var failCount = 0
    public static var failures: [(test: String, message: String)] = []

    public static func run(_ name: String, _ block: () throws -> Void) {
        do {
            try block()
            passCount += 1
            print("  ✅ \(name)")
        } catch {
            failCount += 1
            let msg = "\(error)"
            failures.append((name, msg))
            print("  ❌ \(name): \(msg)")
        }
    }

    public static func summary() {
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Total: \(passCount + failCount)  Pass: \(passCount)  Fail: \(failCount)")
        if !failures.isEmpty {
            print("\nFailures:")
            for f in failures {
                print("  • \(f.test): \(f.message)")
            }
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    }

    public static var allPassed: Bool { failCount == 0 }
}

public struct AssertionError: Error, CustomStringConvertible {
    public let description: String
    public init(_ msg: String) { self.description = msg }
}

public func assertEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    guard a == b else {
        throw AssertionError("Expected \(a) == \(b)  (\(file):\(line))")
    }
}

public func assertTrue(_ value: Bool, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard value else {
        throw AssertionError("Expected true\(msg.isEmpty ? "" : ": \(msg)")  (\(file):\(line))")
    }
}

public func assertFalse(_ value: Bool, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard !value else {
        throw AssertionError("Expected false\(msg.isEmpty ? "" : ": \(msg)")  (\(file):\(line))")
    }
}
