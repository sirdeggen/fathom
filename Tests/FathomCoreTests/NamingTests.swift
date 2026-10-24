import XCTest
@testable import FathomCore

final class NamingTests: XCTestCase {
    func testCanonicalFolding() {
        XCTAssertEqual(canonicalName("Côte d'Ivoire"), "cote divoire")
        XCTAssertEqual(canonicalName("cote d’ivoire"), "cote divoire")
        XCTAssertEqual(canonicalName("COTE D IVOIRE"), "cote d ivoire")
        XCTAssertEqual(canonicalName("The Bahamas"), "bahamas")
        XCTAssertEqual(canonicalName("St. Kitts and Nevis"), "saint kitts and nevis")
        XCTAssertEqual(canonicalName("São Tomé and Príncipe"), "sao tome and principe")
        XCTAssertEqual(canonicalName("Curaçao"), "curacao")
        XCTAssertEqual(canonicalName("Åland"), "aland")
        XCTAssertEqual(canonicalName("Guinea-Bissau"), "guinea bissau")
    }

    func testExactMatchAndAliases() {
        let index = NameIndex(regions: sampleRegions)
        XCTAssertEqual(index.match(query: "cote d'ivoire")?.id, "CIV")
        XCTAssertEqual(index.match(query: "Ivory Coast")?.id, "CIV")
        XCTAssertEqual(index.match(query: "usa")?.id, "USA")
        XCTAssertEqual(index.match(query: "Czech Republic")?.id, "CZE")
        XCTAssertNil(index.match(query: "cote"))
        XCTAssertNil(index.match(query: ""))
        XCTAssertNil(index.match(query: "United States", excluding: ["USA"]))
    }

    func testCongoIsNotAmbiguousOnExactMatch() {
        let index = NameIndex(regions: sampleRegions)
        XCTAssertEqual(index.match(query: "Congo")?.id, "COG")
        XCTAssertEqual(index.match(query: "DR Congo")?.id, "COD")
        XCTAssertEqual(index.match(query: "DRC")?.id, "COD")
    }

    func testSuggestionRanking() {
        let index = NameIndex(regions: sampleRegions)
        let niger = index.suggestions(query: "nig").map(\.id)
        XCTAssertEqual(niger.first, "NER")
        XCTAssertTrue(niger.contains("NGA"))

        let north = index.suggestions(query: "north").map(\.name)
        XCTAssertEqual(north, ["North Korea", "North Macedonia"])

        let prefix = index.suggestions(query: "saint k").map(\.id)
        XCTAssertEqual(prefix, ["KNA"])

        let excluded = index.suggestions(query: "united", excluding: ["USA", "GBR"]).map(\.id)
        XCTAssertEqual(excluded, ["ARE"])
        XCTAssertTrue(index.suggestions(query: "").isEmpty)
    }

    private var sampleRegions: [Region] {
        [
            Region(id: "CIV", name: "Côte d'Ivoire", aliases: ["Ivory Coast"]),
            Region(id: "USA", name: "United States", aliases: ["USA", "US", "United States of America"]),
            Region(id: "GBR", name: "United Kingdom", aliases: ["UK", "Britain"]),
            Region(id: "ARE", name: "United Arab Emirates", aliases: ["UAE"]),
            Region(id: "CZE", name: "Czechia", aliases: ["Czech Republic"]),
            Region(id: "COG", name: "Republic of the Congo", aliases: ["Congo"]),
            Region(id: "COD", name: "DR Congo", aliases: ["DRC", "Democratic Republic of the Congo"]),
            Region(id: "NER", name: "Niger"),
            Region(id: "NGA", name: "Nigeria"),
            Region(id: "PRK", name: "North Korea"),
            Region(id: "MKD", name: "North Macedonia", aliases: ["Macedonia"]),
            Region(id: "KNA", name: "Saint Kitts and Nevis"),
        ]
    }
}
