import XCTest
@testable import FathomCore

final class GeoTests: XCTestCase {
    func testIdenticalPointsHaveNoDistance() {
        let distance = greatCircleDistanceKilometers(
            latitude1: 41.0, longitude1: -74.0,
            latitude2: 41.0, longitude2: -74.0
        )
        XCTAssertEqual(distance, 0, accuracy: 1e-6)
        XCTAssertEqual(
            initialBearingDegrees(
                latitude1: 41.0, longitude1: -74.0,
                latitude2: 41.0, longitude2: -74.0
            ),
            0,
            accuracy: 1e-6
        )
        XCTAssertEqual(proximityPercent(distanceKilometers: 0), 100)
    }

    func testLondonToParis() {
        let distance = greatCircleDistanceKilometers(
            latitude1: 51.5074, longitude1: -0.1278,
            latitude2: 48.8566, longitude2: 2.3522
        )
        XCTAssertEqual(distance, 343.556, accuracy: 0.01)
    }

    func testEquatorQuarterAndHalf() {
        let quarter = greatCircleDistanceKilometers(
            latitude1: 0, longitude1: 0,
            latitude2: 0, longitude2: 90
        )
        XCTAssertEqual(quarter, 10_007.557, accuracy: 0.01)
        XCTAssertEqual(
            initialBearingDegrees(latitude1: 0, longitude1: 0, latitude2: 0, longitude2: 90),
            90,
            accuracy: 0.001
        )

        let half = greatCircleDistanceKilometers(
            latitude1: 0, longitude1: 0,
            latitude2: 0, longitude2: 180
        )
        XCTAssertEqual(half, Earth.halfCircumferenceKilometers, accuracy: 0.01)
        XCTAssertEqual(proximityPercent(distanceKilometers: half), 0)
    }

    func testCardinalBearings() {
        XCTAssertEqual(
            initialBearingDegrees(latitude1: 0, longitude1: 0, latitude2: 10, longitude2: 0),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            initialBearingDegrees(latitude1: 10, longitude1: 0, latitude2: 0, longitude2: 0),
            180,
            accuracy: 0.001
        )
        XCTAssertEqual(
            initialBearingDegrees(latitude1: 0, longitude1: 10, latitude2: 0, longitude2: 0),
            270,
            accuracy: 0.001
        )
    }

    func testBearingWrapsIntoRange() {
        let bearing = initialBearingDegrees(
            latitude1: 10, longitude1: 170,
            latitude2: 12, longitude2: -170
        )
        XCTAssertGreaterThanOrEqual(bearing, 0)
        XCTAssertLessThan(bearing, 360)
    }

    func testCompassBoundaries() {
        XCTAssertEqual(compassName(bearingDegrees: 0), "north")
        XCTAssertEqual(compassName(bearingDegrees: 22.4), "north")
        XCTAssertEqual(compassName(bearingDegrees: 22.5), "northeast")
        XCTAssertEqual(compassName(bearingDegrees: 45), "northeast")
        XCTAssertEqual(compassName(bearingDegrees: 337.4), "northwest")
        XCTAssertEqual(compassName(bearingDegrees: 337.5), "north")
        XCTAssertEqual(compassArrow(bearingDegrees: 90), "➡️")
        XCTAssertEqual(compassArrow(bearingDegrees: 180), "⬇️")
        XCTAssertEqual(compassArrow(bearingDegrees: -90), "⬅️")
    }

    func testMilesConversion() {
        XCTAssertEqual(Earth.miles(fromKilometers: 100), 62.137, accuracy: 0.001)
    }

    func testProximityIsMonotonic() {
        let near = proximityPercent(distanceKilometers: 100)
        let mid = proximityPercent(distanceKilometers: 5_000)
        let far = proximityPercent(distanceKilometers: 15_000)
        XCTAssertGreaterThan(near, mid)
        XCTAssertGreaterThan(mid, far)
        XCTAssertEqual(proximityPercent(distanceKilometers: -5), 100)
        XCTAssertEqual(proximityPercent(distanceKilometers: 50_000), 0)
    }
}
