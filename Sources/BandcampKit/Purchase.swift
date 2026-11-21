import Foundation

public struct Purchase: Codable, Sendable, Equatable {
    public enum ItemType: Codable, Sendable, Equatable, CustomStringConvertible {
        case album, track, package
        case other(String)

        public init(rawValue: String) {
            switch rawValue {
            case "album": self = .album
            case "track": self = .track
            case "package": self = .package
            default: self = .other(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .album: "album"
            case .track: "track"
            case .package: "package"
            case .other(let value): value
            }
        }

        public var description: String { rawValue }

        public init(from decoder: any Decoder) throws {
            self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public var saleItemID: Int
    public var itemType: ItemType
    public var artist: String
    public var title: String
    public var purchasedAt: Date
    public var itemURL: URL?
    /// Captured now for downloading in a later step.
    public var redownloadURL: URL?

    public init(
        saleItemID: Int, itemType: ItemType, artist: String, title: String,
        purchasedAt: Date, itemURL: URL?, redownloadURL: URL?
    ) {
        self.saleItemID = saleItemID
        self.itemType = itemType
        self.artist = artist
        self.title = title
        self.purchasedAt = purchasedAt
        self.itemURL = itemURL
        self.redownloadURL = redownloadURL
    }
}

/// One page of `fancollection/1/collection_items`.
struct CollectionPage: Decodable {
    struct Item: Decodable {
        let sale_item_id: Int
        /// Prefixes the `redownload_urls` key: `p` for purchases, `c` for redeemed codes.
        let sale_item_type: String?
        let item_type: String
        let band_name: String
        let item_title: String
        let purchased: String
        let item_url: String?
    }

    let more_available: Bool
    let last_token: String?
    let items: [Item]
    let redownload_urls: [String: String]?

    func purchases() throws -> [Purchase] {
        try items.map { item in
            guard let date = Self.parseDate(item.purchased) else {
                throw BandcampError.decoding("unparseable purchase date \"\(item.purchased)\"")
            }
            return Purchase(
                saleItemID: item.sale_item_id,
                itemType: .init(rawValue: item.item_type),
                artist: item.band_name,
                title: item.item_title,
                purchasedAt: date,
                itemURL: item.item_url.flatMap(URL.init(string:)),
                redownloadURL: redownload_urls?["\(item.sale_item_type ?? "p")\(item.sale_item_id)"].flatMap(URL.init(string:)))
        }
    }

    /// Parses Bandcamp's `21 Nov 2026 10:00:00 GMT`.
    static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: string)
    }
}
