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
///   - interactive: whether `prompt` may be called (stdin is a TTY, or the app has a window to ask in).
///   - prompt: asks the user for a cookie; empty or nil aborts.
///   - saved: told where a newly entered cookie was saved.
///
/// Runs on the caller's actor, so an app can pass closures that touch its main-actor state.
public func withIdentity<T: Sendable>(
    isolation: isolated (any Actor)? = #isolation,
    credentials: Credentials,
    interactive: Bool,
    prompt: (PromptReason) async throws -> String?,
    saved: (URL) -> Void = { _ in },
    operation: (String) async throws -> T
) async throws -> T {
    var identity = ""
    let source: Credentials.Source
    // Why to ask for a cookie before the next try, if we need to.
    var ask: PromptReason?
    if let found = try credentials.resolve() {
        (identity, source) = found
    } else {
        guard interactive else { throw BandcampError.missingCredentials }
        source = .file(credentials.fileURL)
        ask = .missing
    }

    while true {
        if let reason = ask {
            identity = Credentials.normalize(try await prompt(reason) ?? "")
            guard !identity.isEmpty else { throw BandcampError.aborted }
            saved(try credentials.save(identity))
        }
        do {
            return try await operation(identity)
        } catch BandcampError.unauthorized {
            if source == .environment { throw BandcampError.unauthorizedFromEnvironment }
            guard interactive else { throw BandcampError.unauthorizedNonInteractive }
            ask = .rejected
        }
    }
}
