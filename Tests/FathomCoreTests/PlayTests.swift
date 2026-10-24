import XCTest
@testable import FathomCore

final class PlayTests: XCTestCase {
    func testRoundEndsOnCorrectGuessOrLimit() {
        var round = Round(answerID: "FRA")
        XCTAssertFalse(round.isOver)
        XCTAssertTrue(round.addGuess("DEU"))
        XCTAssertFalse(round.addGuess("DEU"))
        XCTAssertFalse(round.isOver)
        XCTAssertTrue(round.addGuess("FRA"))
        XCTAssertTrue(round.isSolved)
        XCTAssertTrue(round.isOver)
        XCTAssertFalse(round.addGuess("ITA"))
        XCTAssertEqual(round.guessIDs, ["DEU", "FRA"])
    }

    func testSixMissesEndTheRound() {
        var round = Round(answerID: "AK")
        for guess in ["AL", "AZ", "CA", "CO", "CT", "DE"] {
            XCTAssertTrue(round.addGuess(guess))
        }
        XCTAssertFalse(round.isSolved)
        XCTAssertTrue(round.isOver)
        XCTAssertFalse(round.addGuess("FL"))
    }

    func testStreakAndDistribution() {
        var stats = ModeStats()
        stats.record(solved: true, guesses: 1, day: "2026-10-22")
        stats.record(solved: true, guesses: 3, day: "2026-10-23")
        XCTAssertEqual(stats.currentStreak, 2)
        XCTAssertEqual(stats.maxStreak, 2)
        XCTAssertEqual(stats.guessCounts[0], 1)
        XCTAssertEqual(stats.guessCounts[2], 1)
        XCTAssertEqual(stats.winPercent, 100)

        stats.record(solved: false, guesses: 6, day: "2026-10-24")
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.maxStreak, 2)
        XCTAssertEqual(stats.failures, 1)
        XCTAssertEqual(stats.played, 3)
        XCTAssertEqual(stats.winPercent, 67)

        stats.record(solved: true, guesses: 2, day: "2026-10-25")
        XCTAssertEqual(stats.currentStreak, 1)
        XCTAssertEqual(stats.lastWinDay, "2026-10-25")

        stats.record(solved: true, guesses: 6, day: "2026-10-27")
        XCTAssertEqual(stats.currentStreak, 1)
        XCTAssertEqual(stats.maxStreak, 2)
    }

    func testSkippedDayBreaksTheStreak() {
        var stats = ModeStats()
        stats.record(solved: true, guesses: 4, day: "2026-10-01")
        stats.record(solved: true, guesses: 4, day: "2026-10-03")
        XCTAssertEqual(stats.currentStreak, 1)
    }

    func testReconcileRecordsAFinishedDayOnce() {
        let progress = DailyProgress(day: "2026-10-23", guessIDs: ["DEU", "FRA"], recorded: false)
        let first = reconcileDaily(
            progress: progress,
            stats: ModeStats(),
            today: "2026-10-24",
            answerID: "FRA"
        )
        XCTAssertNil(first.progress)
        XCTAssertEqual(first.stats.played, 1)
        XCTAssertEqual(first.stats.wins, 1)
        XCTAssertEqual(first.stats.currentStreak, 1)
        XCTAssertEqual(first.stats.guessCounts[1], 1)

        let again = reconcileDaily(
            progress: DailyProgress(day: "2026-10-23", guessIDs: ["DEU", "FRA"], recorded: true),
            stats: first.stats,
            today: "2026-10-24",
            answerID: "FRA"
        )
        XCTAssertEqual(again.stats.played, 1)
    }

    func testReconcileDropsAnAbandonedDay() {
        let result = reconcileDaily(
            progress: DailyProgress(day: "2026-10-23", guessIDs: ["DEU"], recorded: false),
            stats: ModeStats(),
            today: "2026-10-24",
            answerID: "FRA"
        )
        XCTAssertNil(result.progress)
        XCTAssertEqual(result.stats.played, 0)
    }

    func testReconcileKeepsTodaysUnfinishedRound() {
        let result = reconcileDaily(
            progress: DailyProgress(day: "2026-10-24", guessIDs: ["DEU"], recorded: false),
            stats: ModeStats(),
            today: "2026-10-24",
            answerID: "FRA"
        )
        XCTAssertEqual(result.progress?.guessIDs, ["DEU"])
        XCTAssertEqual(result.progress?.recorded, false)
        XCTAssertEqual(result.stats.played, 0)
    }

    func testShareText() {
        let win = shareText(
            modeTitle: "Countries",
            day: "2026-10-24",
            guesses: [
                ShareGuess(arrow: "↗️", proximity: 96, correct: false),
                ShareGuess(arrow: nil, proximity: 100, correct: true),
            ]
        )
        XCTAssertEqual(
            win,
            """
            Fathom · Countries
            Oct 24, 2026 · 2/6
            ↗️ 96%
            🎯
            """
        )

        let loss = shareText(
            modeTitle: "States",
            day: "2026-01-01",
            guesses: [
                ShareGuess(arrow: "⬅️", proximity: 40, correct: false),
            ]
        )
        XCTAssertEqual(
            loss,
            """
            Fathom · States
            Jan 1, 2026 · ✕/6
            ⬅️ 40%
            """
        )
    }
}
