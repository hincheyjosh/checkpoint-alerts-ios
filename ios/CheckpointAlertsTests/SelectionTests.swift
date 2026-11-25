import XCTest
@testable import CheckpointAlerts

/// Selection rules, ported from the Android app's RefreshWorkerTest and
/// HourlyReminderWorkerTest. The warning covers both days around a
/// checkpoint: checkpoints usually run around midnight, so a checkpoint
/// dated tomorrow warns today ("tomorrow") and again tomorrow ("today").
final class SelectionTests: XCTestCase {

    private func checkpoint(id: String, date: Date, county: String = "Sevier") -> Checkpoint {
        Checkpoint(
            id: id,
            stateCode: "TN",
            county: county,
            city: "",
            location: "Some Road",
            date: date,
            type: .sobriety,
            sourceUrl: ""
        )
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day))!
    }

    private func days(_ date: Date, _ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: date)!
    }

    // MARK: - selectToNotify

    func testSelectsTodayAndTomorrowOnly() {
        let today = day(2026, 11, 20)
        let list = [
            checkpoint(id: "past", date: days(today, -1)),
            checkpoint(id: "today", date: today),
            checkpoint(id: "tomorrow", date: days(today, 1)),
            checkpoint(id: "later", date: days(today, 2)),
        ]
        let result = CheckpointRepository.selectToNotify(
            checkpoints: list, today: today, inScope: { _ in true }, wasNotified: { _ in false })
        XCTAssertEqual(result.map(\.id), ["today", "tomorrow"])
    }

    func testSelectToNotifyRespectsScopeAndAlreadyNotified() {
        let today = day(2026, 11, 20)
        let list = [
            checkpoint(id: "today-out-of-scope", date: today, county: "Davidson"),
            checkpoint(id: "today-notified", date: today),
            checkpoint(id: "tomorrow-ok", date: days(today, 1)),
        ]
        let result = CheckpointRepository.selectToNotify(
            checkpoints: list, today: today,
            inScope: { $0.county == "Sevier" },
            wasNotified: { $0 == "today-notified" }
        )
        XCTAssertEqual(result.map(\.id), ["tomorrow-ok"])
    }

    // MARK: - selectTodays

    private func select(
        _ checkpoints: [Checkpoint],
        today: Date,
        hour: Int = 12,
        notificationsEnabled: Bool = true,
        hourlyRemindersEnabled: Bool = true,
        inScope: (Checkpoint) -> Bool = { _ in true }
    ) -> [Checkpoint] {
        CheckpointRepository.selectTodays(
            checkpoints: checkpoints, today: today, hour: hour,
            notificationsEnabled: notificationsEnabled,
            hourlyRemindersEnabled: hourlyRemindersEnabled,
            inScope: inScope
        )
    }

    func testNotifiesForTodayCheckpointInScopeDuringHours() {
        let today = day(2026, 11, 20)
        let result = select([checkpoint(id: "today", date: today)], today: today)
        XCTAssertEqual(result.map(\.id), ["today"])
    }

    func testNoNotificationWhenHourlyToggleOff() {
        let today = day(2026, 11, 20)
        let result = select(
            [checkpoint(id: "today", date: today)], today: today,
            hourlyRemindersEnabled: false)
        XCTAssertTrue(result.isEmpty)
    }

    func testNoNotificationWhenMasterNotificationsOff() {
        let today = day(2026, 11, 20)
        let result = select(
            [checkpoint(id: "today", date: today)], today: today,
            notificationsEnabled: false)
        XCTAssertTrue(result.isEmpty)
    }

    func testNoNotificationWhenNoCheckpointsToday() {
        let today = day(2026, 11, 20)
        let result = select([
            checkpoint(id: "yesterday", date: days(today, -1)),
            checkpoint(id: "tomorrow", date: days(today, 1)),
        ], today: today)
        XCTAssertTrue(result.isEmpty)
    }

    func testNoNotificationBefore7am() {
        let today = day(2026, 11, 20)
        let result = select([checkpoint(id: "today", date: today)], today: today, hour: 6)
        XCTAssertTrue(result.isEmpty)
    }

    func testNoNotificationAfter10pm() {
        let today = day(2026, 11, 20)
        let result = select([checkpoint(id: "today", date: today)], today: today, hour: 23)
        XCTAssertTrue(result.isEmpty)
    }

    func testNotifiesAt7amAnd10pmBoundaries() {
        let today = day(2026, 11, 20)
        let list = [checkpoint(id: "today", date: today)]
        XCTAssertEqual(select(list, today: today, hour: 7).map(\.id), ["today"])
        XCTAssertEqual(select(list, today: today, hour: 22).map(\.id), ["today"])
    }

    func testNoNotificationForOutOfScopeCheckpoint() {
        let today = day(2026, 11, 20)
        let result = select(
            [checkpoint(id: "today-far", date: today, county: "Davidson")],
            today: today,
            inScope: { $0.county == "Sevier" })
        XCTAssertTrue(result.isEmpty)
    }

    func testOnlyTodaysCheckpointsAreReturned() {
        let today = day(2026, 11, 20)
        let list = [
            checkpoint(id: "today", date: today),
            checkpoint(id: "tomorrow", date: days(today, 1)),
            checkpoint(id: "yesterday", date: days(today, -1)),
        ]
        XCTAssertEqual(select(list, today: today).map(\.id), ["today"])
    }

    // MARK: - County scope

    func testScopeCountiesIncludesHomeAndNeighbors() {
        // Sevier touches Blount, Cocke, Jefferson, and Knox.
        XCTAssertEqual(
            TnCounties.scopeCounties(homeCounty: "Sevier"),
            ["Sevier", "Blount", "Cocke", "Jefferson", "Knox"])
        XCTAssertEqual(TnCounties.all.count, 95)
    }
}
