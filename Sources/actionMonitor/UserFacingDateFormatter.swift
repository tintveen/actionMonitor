import Foundation

enum UserFacingDateFormatter {
    static let englishLocale = Locale(identifier: "en_US_POSIX")

    static func relativeTimestamp(
        _ timestamp: Date,
        relativeTo referenceDate: Date = .now,
        unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .short,
        locale: Locale = englishLocale
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = unitsStyle
        formatter.locale = locale
        return formatter.localizedString(for: timestamp, relativeTo: referenceDate)
    }

    static func shortTime(
        _ date: Date,
        timeZone: TimeZone = .current,
        locale: Locale = englishLocale
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = locale
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
