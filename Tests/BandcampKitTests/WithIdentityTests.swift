import Foundation
import Testing

@testable import BandcampKit

/// Hands out canned answers and records what was asked.
final class ScriptedPrompt {
    var answers: [String?]
    var reasons: [PromptReason] = []

    init(_ answers: [String?]) { self.answers = answers }

    func callAsFunction(_ reason: PromptReason) -> String? {
        reasons.append(reason)
        return answers.isEmpty ? nil : answers.removeFirst()
    }
}

/// Accepts only `valid` and records the cookies it was called with.
final class Operation {
    let valid: String
    var calls: [String] = []

    init(accepting valid: String) { self.valid = valid }

    func callAsFunction(_ identity: String) async throws -> String {
        calls.append(identity)
        guard identity == valid else { throw BandcampError.unauthorized }
        return "ok:\(identity)"
    }
}

@Suite struct WithIdentityTests {
    let directory = temporaryDirectory()

    @Test func usesSavedCookieWithoutPrompting() async throws {
        let credentials = Credentials(directory: directory, environment: [:])
        try credentials.save("good")
        let prompt = ScriptedPrompt([])
        let operation = Operation(accepting: "good")

        let result = try await withIdentity(
            credentials: credentials, interactive: true, prompt: prompt.callAsFunction,
            operation: operation.callAsFunction)

        #expect(result == "ok:good")
        #expect(prompt.reasons.isEmpty)
    }

    @Test func promptsWhenMissingAndSaves() async throws {
        let credentials = Credentials(directory: directory, environment: [:])
        let prompt = ScriptedPrompt([" good\n"])
        let operation = Operation(accepting: "good")
        var savedTo: [URL] = []

        let result = try await withIdentity(
            credentials: credentials, interactive: true, prompt: prompt.callAsFunction,
            saved: { savedTo.append($0) }, operation: operation.callAsFunction)

        #expect(result == "ok:good")
        #expect(prompt.reasons == [.missing])
        #expect(savedTo == [credentials.fileURL])
        #expect(try credentials.resolve()?.identity == "good")
    }

    @Test func missingAndNotInteractiveFails() async throws {
        let credentials = Credentials(directory: directory, environment: [:])
        let prompt = ScriptedPrompt(["good"])

        await #expect(throws: BandcampError.missingCredentials) {
            try await withIdentity(
                credentials: credentials, interactive: false, prompt: prompt.callAsFunction,
                operation: Operation(accepting: "good").callAsFunction)
        }
        #expect(prompt.reasons.isEmpty)
    }

    @Test func rejectedCookieIsReplacedAndRetried() async throws {
        let credentials = Credentials(directory: directory, environment: [:])
        try credentials.save("expired")
        let prompt = ScriptedPrompt(["also-bad", "good"])
        let operation = Operation(accepting: "good")

        let result = try await withIdentity(
            credentials: credentials, interactive: true, prompt: prompt.callAsFunction,
            operation: operation.callAsFunction)

        #expect(result == "ok:good")
        #expect(prompt.reasons == [.rejected, .rejected])
        #expect(operation.calls == ["expired", "also-bad", "good"])
        #expect(try credentials.resolve()?.identity == "good")
    }

    @Test func emptyInputAborts() async throws {
        let credentials = Credentials(directory: directory, environment: [:])
        try credentials.save("expired")
        let prompt = ScriptedPrompt(["  "])

        await #expect(throws: BandcampError.aborted) {
            try await withIdentity(
                credentials: credentials, interactive: true, prompt: prompt.callAsFunction,
                operation: Operation(accepting: "good").callAsFunction)
        }
        #expect(try credentials.resolve()?.identity == "expired")
    }

    @Test func endOfInputAborts() async throws {
        let credentials = Credentials(directory: directory, environment: [:])
        await #expect(throws: BandcampError.aborted) {
            try await withIdentity(
                credentials: credentials, interactive: true, prompt: ScriptedPrompt([nil]).callAsFunction,
                operation: Operation(accepting: "good").callAsFunction)
        }
    }

    @Test func rejectedEnvironmentCookieFailsWithoutPrompting() async throws {
        let credentials = Credentials(directory: directory, environment: ["BANDCAMP_IDENTITY": "expired"])
        let prompt = ScriptedPrompt(["good"])

        await #expect(throws: BandcampError.unauthorizedFromEnvironment) {
            try await withIdentity(
                credentials: credentials, interactive: true, prompt: prompt.callAsFunction,
                operation: Operation(accepting: "good").callAsFunction)
        }
        #expect(prompt.reasons.isEmpty)
    }

    @Test func rejectedAndNotInteractiveFailsWithoutPrompting() async throws {
        let credentials = Credentials(directory: directory, environment: [:])
        try credentials.save("expired")
        let prompt = ScriptedPrompt(["good"])

        await #expect(throws: BandcampError.unauthorizedNonInteractive) {
            try await withIdentity(
                credentials: credentials, interactive: false, prompt: prompt.callAsFunction,
                operation: Operation(accepting: "good").callAsFunction)
        }
        #expect(prompt.reasons.isEmpty)
    }

    @Test func otherErrorsPassThrough() async throws {
        let credentials = Credentials(directory: directory, environment: [:])
        try credentials.save("good")
        let prompt = ScriptedPrompt(["x"])

        await #expect(throws: BandcampError.http(status: 500)) {
            try await withIdentity(
                credentials: credentials, interactive: true, prompt: prompt.callAsFunction,
                operation: { _ in throw BandcampError.http(status: 500) })
        }
        #expect(prompt.reasons.isEmpty)
    }
}
