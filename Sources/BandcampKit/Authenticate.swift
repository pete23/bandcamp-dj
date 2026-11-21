import Foundation

/// Why the user is being asked for a cookie.
public enum PromptReason: Sendable, Equatable {
    case missing
    case rejected
}

/// Runs `operation` with the identity cookie, asking for one when there is none
/// or when Bandcamp rejects it, and saving what the user enters.
///
/// - Parameters:
///   - interactive: whether `prompt` may be called (stdin is a TTY).
///   - prompt: asks the user for a cookie; empty or nil aborts.
///   - saved: told where a newly entered cookie was saved.
public func withIdentity<T>(
    credentials: Credentials,
    interactive: Bool,
    prompt: (PromptReason) throws -> String?,
    saved: (URL) -> Void = { _ in },
    operation: (String) async throws -> T
) async throws -> T {
    func ask(_ reason: PromptReason) throws -> String {
        let value = Credentials.normalize(try prompt(reason) ?? "")
        guard !value.isEmpty else { throw BandcampError.aborted }
        saved(try credentials.save(value))
        return value
    }

    var identity: String
    let source: Credentials.Source
    if let found = try credentials.resolve() {
        (identity, source) = found
    } else {
        guard interactive else { throw BandcampError.missingCredentials }
        identity = try ask(.missing)
        source = .file(credentials.fileURL)
    }

    while true {
        do {
            return try await operation(identity)
        } catch BandcampError.unauthorized {
            if source == .environment { throw BandcampError.unauthorizedFromEnvironment }
            guard interactive else { throw BandcampError.unauthorizedNonInteractive }
            identity = try ask(.rejected)
        }
    }
}
