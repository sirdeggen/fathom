import XCTest
@testable import FathomCore

final class CatalogTests: XCTestCase {
    func testCatalogLoads() throws {
        let catalog = try RegionDatabase.load()
        XCTAssertEqual(catalog.states.count, 50)
        XCTAssertFalse(catalog.states.contains { $0.id == "DC" || $0.name == "District of Columbia" })
        XCTAssertEqual(Set(catalog.states.map(\.id)).count, 50)
        XCTAssertTrue((170...210).contains(catalog.countries.count))
        XCTAssertTrue(catalog.attribution.contains("Natural Earth"))
        XCTAssertEqual(catalog.countries.map(\.id), catalog.countries.map(\.id).sorted())
        XCTAssertEqual(catalog.states.map(\.id), catalog.states.map(\.id).sorted())
    }

    func testOutlinesStayInsideTheirBoxes() throws {
        let catalog = try RegionDatabase.load()
        for region in catalog.countries + catalog.states {
            XCTAssertGreaterThan(region.width, 1, region.id)
            XCTAssertGreaterThan(region.height, 1, region.id)
            XCTAssertLessThan(region.aspectRatio, 18, region.id)
            XCTAssertFalse(region.polygons.isEmpty, region.id)
            XCTAssertTrue((-90...90).contains(region.latitude), region.id)
            XCTAssertTrue((-180...180).contains(region.longitude), region.id)
            for polygon in region.polygons {
                for ring in polygon {
                    XCTAssertGreaterThanOrEqual(ring.count, 6, region.id)
                    XCTAssertEqual(ring.count % 2, 0, region.id)
                    for index in stride(from: 0, to: ring.count, by: 2) {
                        XCTAssertTrue((0...region.width).contains(ring[index]), region.id)
                        XCTAssertTrue((0...region.height).contains(ring[index + 1]), region.id)
                    }
                }
            }
        }
    }

    func testRecognizableCentroids() throws {
        let catalog = try RegionDatabase.load()
        func country(_ id: String) throws -> Region {
            try XCTUnwrap(catalog.countries.first { $0.id == id })
        }
        func state(_ id: String) throws -> Region {
            try XCTUnwrap(catalog.states.first { $0.id == id })
        }

        let france = try country("FRA")
        XCTAssertEqual(france.name, "France")
        XCTAssertEqual(france.latitude, 46.5, accuracy: 2)
        XCTAssertEqual(france.longitude, 2.5, accuracy: 3)

        let unitedStates = try country("USA")
        XCTAssertEqual(unitedStates.name, "United States")
        XCTAssertEqual(unitedStates.latitude, 40, accuracy: 3)
        XCTAssertEqual(unitedStates.longitude, -99, accuracy: 8)

        let fiji = try country("FJI")
        XCTAssertEqual(fiji.latitude, -17.5, accuracy: 2)
        XCTAssertGreaterThan(abs(fiji.longitude), 170)
        XCTAssertLessThan(fiji.aspectRatio, 5)

        let chile = try country("CHL")
        XCTAssertGreaterThan(chile.height, chile.width)
        XCTAssertEqual(chile.longitude, -71, accuracy: 4)

        let norway = try country("NOR")
        XCTAssertEqual(norway.latitude, 64, accuracy: 4)
        XCTAssertLessThan(norway.latitude, 72)

        let spain = try country("ESP")
        XCTAssertGreaterThan(spain.latitude, 36)
        XCTAssertLessThan(spain.longitude, 5)

        let southAfrica = try country("ZAF")
        XCTAssertTrue(southAfrica.polygons.contains { $0.count > 1 })
        XCTAssertEqual(southAfrica.latitude, -29, accuracy: 4)

        let russia = try country("RUS")
        XCTAssertEqual(russia.latitude, 62, accuracy: 8)
        XCTAssertEqual(russia.longitude, 100, accuracy: 25)
        XCTAssertLessThan(russia.aspectRatio, 8)

        let ivoryCoast = try country("CIV")
        XCTAssertEqual(ivoryCoast.name, "Côte d'Ivoire")

        let alaska = try state("AK")
        XCTAssertEqual(alaska.latitude, 64, accuracy: 4)
        XCTAssertEqual(alaska.longitude, -152, accuracy: 12)
        XCTAssertLessThan(alaska.aspectRatio, 8)

        let hawaii = try state("HI")
        XCTAssertEqual(hawaii.latitude, 20.5, accuracy: 2)
        XCTAssertEqual(hawaii.longitude, -157, accuracy: 4)

        let florida = try state("FL")
        XCTAssertEqual(florida.latitude, 28.5, accuracy: 2)
        XCTAssertEqual(florida.longitude, -82.5, accuracy: 3)

        XCTAssertEqual(try state("CA").name, "California")
        XCTAssertEqual(try state("NY").name, "New York")
    }

    func testRealNamesResolve() throws {
        let catalog = try RegionDatabase.load()
        let countries = NameIndex(regions: catalog.countries)
        XCTAssertEqual(countries.match(query: "cote d'ivoire")?.id, "CIV")
        XCTAssertEqual(countries.match(query: "usa")?.id, "USA")
        XCTAssertEqual(countries.match(query: "Czech Republic")?.id, "CZE")
        XCTAssertEqual(countries.match(query: "st kitts and nevis")?.id, "KNA")
        XCTAssertEqual(countries.match(query: "Congo")?.id, "COG")
        let states = NameIndex(regions: catalog.states)
        XCTAssertEqual(states.match(query: "rhode island")?.id, "RI")
        XCTAssertEqual(states.suggestions(query: "new").map(\.id).sorted(), ["NH", "NJ", "NM", "NY"])

        for region in catalog.countries + catalog.states {
            let index = NameIndex(regions: region.id.count == 2 ? catalog.states : catalog.countries)
            XCTAssertEqual(index.match(query: region.name)?.id, region.id, region.name)
            for alias in region.aliases {
                XCTAssertEqual(index.match(query: alias)?.id, region.id, "\(region.id) alias \(alias)")
            }
        }
    }

    func testDailyPickIsInsideTheCatalog() throws {
        let catalog = try RegionDatabase.load()
        let index = dailyIndex(
            mode: PuzzleMode.countries.rawValue,
            date: "2026-10-24",
            count: catalog.countries.count
        )
        XCTAssertTrue(catalog.countries.indices.contains(index))
        let again = dailyIndex(
            mode: PuzzleMode.countries.rawValue,
            date: "2026-10-24",
            count: catalog.countries.count
        )
        XCTAssertEqual(catalog.countries[index].id, catalog.countries[again].id)
    }
}
