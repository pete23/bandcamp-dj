import Foundation

public enum BandcampError: Error, Equatable, Sendable {
    /// No identity cookie was found and we can't ask for one.
    case missingCredentials
    /// Bandcamp rejected the identity cookie.
    case unauthorized
    /// Bandcamp rejected the cookie from `BANDCAMP_IDENTITY`, which we won't override.
    case unauthorizedFromEnvironment
    /// Bandcamp rejected the saved cookie and we can't ask for a new one.
    case unauthorizedNonInteractive
    /// The user entered nothing when asked for a cookie.
    case aborted
    case http(status: Int)
    case decoding(String)
    case formatUnavailable(format: String, available: [String])
    /// A web page came back where the audio file should be.
    case notAFile
}

extension BandcampError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .missingCredentials:
            "No Bandcamp identity cookie found.\n\n\(Credentials.instructions)"
        case .unauthorized:
            "Bandcamp rejected the identity cookie (rejected or expired)."
        case .unauthorizedFromEnvironment:
            "Bandcamp rejected the identity cookie in \(Credentials.environmentVariable) "
                + "(rejected or expired). Update or unset the variable."
        case .unauthorizedNonInteractive:
            "Bandcamp rejected the saved identity cookie (rejected or expired). "
                + "Run bandcamp-sync interactively to enter a new one."
        case .aborted:
            "No identity cookie entered; aborting."
        case .http(let status):
            "Bandcamp returned HTTP \(status)."
        case .decoding(let detail):
            "Unexpected response from Bandcamp: \(detail)"
        case .formatUnavailable(let format, let available):
            "\(format) isn't offered for this item (available: \(available.joined(separator: ", ")))."
        case .notAFile:
            "Bandcamp sent a web page instead of the file; the download link may have expired."
        }
    }
}
