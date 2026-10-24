import Foundation

public struct Region: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let latitude: Double
    public let longitude: Double
    /// Pixel width of the outline's box. Y grows south.
    public let width: Int
    public let height: Int
    /// Polygons of rings. Each ring is a flat list of x, y integer pairs.
    /// The first ring is the exterior; later rings are holes.
    public let polygons: [[[Int]]]

    public init(
        id: String,
        name: String,
        aliases: [String] = [],
        latitude: Double = 0,
        longitude: Double = 0,
        width: Int = 10,
        height: Int = 10,
        polygons: [[[Int]]] = [[[0, 0, 10, 0, 0, 10]]]
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.latitude = latitude
        self.longitude = longitude
        self.width = width
        self.height = height
        self.polygons = polygons
    }

    public var aspectRatio: Double {
        Double(max(width, height)) / Double(max(1, min(width, height)))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, polygons
        case latitude = "lat"
        case longitude = "lon"
        case width = "w"
        case height = "h"
    }
}

public struct RegionCatalog: Equatable, Sendable {
    public let attribution: String
    public let countries: [Region]
    public let states: [Region]

    public init(attribution: String, countries: [Region], states: [Region]) {
        self.attribution = attribution
        self.countries = countries.sorted { $0.id < $1.id }
        self.states = states.sorted { $0.id < $1.id }
    }

    public func regions(for mode: PuzzleMode) -> [Region] {
        switch mode {
        case .countries: return countries
        case .states: return states
        }
    }

    public func region(id: String, mode: PuzzleMode) -> Region? {
        regions(for: mode).first { $0.id == id }
    }
}

public enum RegionDatabaseError: Error, Equatable {
    case missingResource
    case unreadable
}

public enum RegionDatabase {
    public static func load() throws -> RegionCatalog {
        let candidates = [
            Bundle.module.url(forResource: "regions", withExtension: "json"),
            Bundle.module.url(forResource: "regions", withExtension: "json", subdirectory: "Resources"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            throw RegionDatabaseError.missingResource
        }
        do {
            return try load(from: Data(contentsOf: url))
        } catch let error as RegionDatabaseError {
            throw error
        } catch {
            throw RegionDatabaseError.unreadable
        }
    }

    public static func load(from data: Data) throws -> RegionCatalog {
        do {
            let decoded = try JSONDecoder().decode(File.self, from: data)
            return RegionCatalog(
                attribution: decoded.attribution,
                countries: decoded.countries,
                states: decoded.states
            )
        } catch {
            throw RegionDatabaseError.unreadable
        }
    }
}

private struct File: Decodable {
    let attribution: String
    let countries: [Region]
    let states: [Region]
}
