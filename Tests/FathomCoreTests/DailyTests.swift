import XCTest
@testable import FathomCore

final class DailyTests: XCTestCase {
    func testIndexIsStableAndInRange() {
        let first = dailyIndex(mode: "countries", date: "2026-10-24", count: 180)
        let second = dailyIndex(mode: "countries", date: "2026-10-24", count: 180)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, 119)
        XCTAssertEqual(dailyIndex(mode: "states", date: "2026-10-24", count: 50), 13)
        XCTAssertEqual(dailyIndex(mode: "countries", date: "2026-10-24", count: 1), 0)
    }

    func testModesAndDatesDiverge() {
        let countries = dailyIndex(mode: "countries", date: "2026-10-24", count: 204)
        let states = dailyIndex(mode: "states", date: "2026-10-24", count: 204)
        XCTAssertNotEqual(countries, states)

        var seen: Set<Int> = []
        for day in 1...30 {
            let date = String(format: "2026-10-%02d", day)
            seen.insert(dailyIndex(mode: "countries", date: date, count: 204))
        }
        XCTAssertGreaterThan(seen.count, 20)
    }

    func testUTCDayAndPreviousDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 10
        components.day = 24
        components.hour = 23
        let late = components.date!
        XCTAssertEqual(utcDayString(from: late), "2026-10-24")

        components.hour = 0
        components.minute = 30
        XCTAssertEqual(utcDayString(from: components.date!), "2026-10-24")

        XCTAssertEqual(previousUTCDay("2026-03-01"), "2026-02-28")
        XCTAssertEqual(previousUTCDay("2024-03-01"), "2024-02-29")
        XCTAssertEqual(previousUTCDay("2026-01-01"), "2025-12-31")
        XCTAssertEqual(previousUTCDay("2026-10-24"), "2026-10-23")
        XCTAssertNil(previousUTCDay("not-a-day"))
    }

    func testShareDateFormatting() {
        XCTAssertEqual(formatShareDate("2026-10-24"), "Oct 24, 2026")
        XCTAssertEqual(formatShareDate("2026-01-01"), "Jan 1, 2026")
        XCTAssertEqual(formatShareDate("nope"), "nope")
    }
}
