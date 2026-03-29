import XCTest
@testable import actionMonitor

final class UserFacingDateFormatterTests: XCTestCase {
    func testRelativeTimestampDefaultsToEnglish() {
        let now = Date(timeIntervalSince1970: 1_743_249_600)
        let fiveDaysAgo = Calendar(identifier: .gregorian).date(byAdding: .day, value: -5, to: now)!

        let englishValue = UserFacingDateFormatter.relativeTimestamp(fiveDaysAgo, relativeTo: now)
        let germanValue = UserFacingDateFormatter.relativeTimestamp(
            fiveDaysAgo,
            relativeTo: now,
            locale: Locale(identifier: "de_DE")
        )

        XCTAssertEqual(englishValue, "5 days ago")
        XCTAssertEqual(germanValue, "vor 5 Tagen")
    }

    func testShortTimeUsesEnglishLocaleWithProvidedTimeZone() {
        let resetAt = ISO8601DateFormatter().date(from: "2026-03-29T14:30:00Z")!

        XCTAssertEqual(
            UserFacingDateFormatter.shortTime(
                resetAt,
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            "2:30\u{202F}PM"
        )
    }
}
