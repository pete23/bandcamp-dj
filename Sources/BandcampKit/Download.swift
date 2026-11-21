import Foundation

/// The Bandcamp download formats Apple Music can import (not FLAC or Ogg Vorbis).
public enum DownloadFormat: String, CaseIterable, Codable, Sendable {
    case mp3320 = "mp3-320"
    case mp3V0 = "mp3-v0"
    case aacHi = "aac-hi"
    case alac
    case aiff = "aiff-lossless"
    case wav

    /// The extension of a single-track download (albums come as a zip).
    public var fileExtension: String {
        switch self {
        case .mp3320, .mp3V0: "mp3"
        case .aacHi, .alac: "m4a"
        case .aiff: "aiff"
        case .wav: "wav"
        }
    }
}

/// One format of a purchase, as offered on its download page.
public struct DownloadOption: Sendable, Equatable {
    public var format: DownloadFormat
    public var url: URL
    /// Bandcamp's own label, e.g. `95.5MB`.
    public var size: String?
}

/// The JSON blob embedded in a `bandcamp.com/download?…` page.
struct DownloadPage: Decodable {
    struct Item: Decodable {
        struct File: Decodable {
            let url: String
            let size_mb: String?
        }

        let title: String?
        let downloads: [String: File]

        enum CodingKeys: String, CodingKey { case title, downloads }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            // Items with no digital download send `[]` or null here.
            downloads = (try? container.decodeIfPresent([String: File].self, forKey: .downloads)) ?? [:]
        }
    }

    let digital_items: [Item]

    static func parse(html: String) throws -> DownloadPage {
        guard let start = html.range(of: "data-blob=\""),
            let end = html[start.upperBound...].firstIndex(of: "\"")
        else { throw BandcampError.decoding("no download data on the download page") }
        let json = unescapeHTML(html[start.upperBound..<end])
        do {
            return try JSONDecoder().decode(DownloadPage.self, from: Data(json.utf8))
        } catch {
            throw BandcampError.decoding("download page: \(error)")
        }
    }

    static func unescapeHTML(_ text: Substring) -> String {
        var result = ""
        var rest = text[...]
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            guard let semi = rest[amp...].firstIndex(of: ";"), rest.distance(from: amp, to: semi) <= 10 else {
                result.append("&")
                rest = rest[rest.index(after: amp)...]
                continue
            }
            let entity = rest[rest.index(after: amp)..<semi]
            let named = ["quot": "\"", "amp": "&", "lt": "<", "gt": ">", "apos": "'", "#39": "'"]
            if let value = named[String(entity)] {
                result += value
            } else if entity.hasPrefix("#x"), let code = UInt32(entity.dropFirst(2), radix: 16),
                let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else if entity.hasPrefix("#"), let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else {
                result += rest[amp...semi]
            }
            rest = rest[rest.index(after: semi)...]
        }
        return result + rest
    }
}

extension BandcampClient {
    /// The download link for `purchase` in `format`, or nil if it has no digital download.
    public func downloadOption(for purchase: Purchase, format: DownloadFormat) async throws -> DownloadOption? {
        guard let pageURL = purchase.redownloadURL else { return nil }
        let (data, status) = try await send(URLRequest(url: pageURL))
        guard (200..<300).contains(status) else { throw BandcampError.http(status: status) }
        let page = try DownloadPage.parse(html: String(decoding: data, as: UTF8.self))

        let offered = page.digital_items.flatMap(\.downloads)
        guard !offered.isEmpty else { return nil }
        guard let file = offered.first(where: { $0.key == format.rawValue })?.value,
            let url = URL(string: file.url)
        else {
            throw BandcampError.formatUnavailable(
                format: format.rawValue, available: offered.map(\.key).sorted())
        }
        return DownloadOption(format: format, url: url, size: file.size_mb)
    }

    /// Downloads `option` to a temporary file the caller then owns.
    public func download(_ option: DownloadOption) async throws -> URL {
        var request = URLRequest(url: try await fileURL(for: option.url))
        request.setValue("identity=\(identity)", forHTTPHeaderField: "Cookie")
        let (file, response) = try await transport.download(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: file)
            throw BandcampError.http(status: status)
        }
        guard !(http?.value(forHTTPHeaderField: "Content-Type") ?? "").hasPrefix("text/html") else {
            try? FileManager.default.removeItem(at: file)
            throw BandcampError.notAFile
        }
        return file
    }

    /// Bandcamp's download links are resolved via `statdownload`, which answers with
    /// `…Downloads.statResult({"result": "ok", "download_url": "…"})…`. Falls back to the
    /// original link if that doesn't give a URL.
    func fileURL(for downloadURL: URL) async throws -> URL {
        guard var components = URLComponents(url: downloadURL, resolvingAgainstBaseURL: false),
            components.path.hasPrefix("/download/")
        else { return downloadURL }
        components.path = "/statdownload/" + components.path.dropFirst("/download/".count)
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: ".vrs", value: "1"),
            URLQueryItem(name: ".rand", value: String(Int.random(in: 0..<1_000_000_000))),
        ]
        guard let statURL = components.url else { return downloadURL }

        let (data, status) = try await send(URLRequest(url: statURL))
        guard (200..<300).contains(status) else { return downloadURL }
        return Self.statDownloadURL(String(decoding: data, as: UTF8.self)) ?? downloadURL
    }

    static func statDownloadURL(_ body: String) -> URL? {
        struct Stat: Decodable { let download_url: String? }
        // The JSON sits inside JavaScript braces, so start at the first `{"` and try each `}` from the end.
        guard let open = body.range(of: "{\"")?.lowerBound else { return nil }
        var end = body.endIndex
        while let close = body[open..<end].lastIndex(of: "}") {
            if let stat = try? JSONDecoder().decode(Stat.self, from: Data(body[open...close].utf8)) {
                return stat.download_url.flatMap(URL.init(string:))
            }
            end = close
        }
        return nil
    }
}
