import Foundation

struct OpeningPeriod: Codable, Hashable, Sendable {
    /// Sunday = 1, matching Calendar and Mapbox Search's DateComponents.
    let weekday: Int
    let startMinute: Int
    let endWeekday: Int
    let endMinute: Int
    var start: Int { (weekday - 1) * 1440 + startMinute }
    var end: Int {
        let raw = (endWeekday - 1) * 1440 + endMinute
        return raw <= start ? raw + 10080 : raw
    }
    var label: String { "\(Self.clock(startMinute)) – \(Self.clock(endMinute))" }
    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60) }
}

struct OpeningSchedule: Codable, Hashable, Sendable {
    enum Availability: String, Codable { case scheduled, alwaysOpen, temporarilyClosed, permanentlyClosed }
    let availability: Availability
    var periods: [OpeningPeriod] = []
    var timeZoneIdentifier: String?
    var note: String?
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        return calendar
    }
    func weekday(at date: Date) -> Int { calendar.component(.weekday, from: date) }
    func hours(for weekday: Int) -> String {
        switch availability {
        case .alwaysOpen: return "Open 24 hours"
        case .temporarilyClosed, .permanentlyClosed: return "Closed"
        case .scheduled:
            let today = periods.filter { $0.weekday == weekday }.sorted { $0.startMinute < $1.startMinute }
            if today.isEmpty { return "Closed" }
            if today.contains(where: { $0.end - $0.start >= 1440 }) { return "Open 24 hours" }
            return today.map(\.label).joined(separator: ", ")
        }
    }
    func status(at date: Date) -> String {
        switch availability {
        case .alwaysOpen: return "Open 24 hours"
        case .temporarilyClosed: return "Temporarily closed"
        case .permanentlyClosed: return "Permanently closed"
        case .scheduled:
            guard timeZoneIdentifier != nil else { return "Opening hours" }
            let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
            let minute = ((components.weekday ?? 1) - 1) * 1440 + (components.hour ?? 0) * 60 + (components.minute ?? 0)
            for period in periods {
                for shifted in [minute, minute + 10080] where shifted >= period.start && shifted < period.end {
                    return "Open now · Closes \(OpeningPeriod.clock(period.endMinute))"
                }
            }
            return "Closed now"
        }
    }
}

enum AddressFormatting {
    static func natural(_ address: String) -> String {
        let connectors: Set<String> = ["and", "of", "the", "upon", "on", "de", "du", "la"]
        let components = address.split(separator: ",", omittingEmptySubsequences: false).map { part in
            part.split(separator: " ").enumerated().map { index, token in
                let text = String(token)
                guard text == text.lowercased(), text.contains(where: \.isLetter) else { return text }
                if index > 0 && connectors.contains(text) { return text }
                return text.prefix(1).uppercased() + text.dropFirst()
            }.joined(separator: " ")
        }.joined(separator: ", ")
        // UK postcodes are identifiers, so keep their conventional uppercase spelling.
        guard let pattern = try? NSRegularExpression(pattern: "\\b[A-Z]{1,2}[0-9][A-Z0-9]?\\s?[0-9][A-Z]{2}\\b", options: .caseInsensitive) else { return components }
        let result = NSMutableString(string: components)
        for match in pattern.matches(in: components, range: NSRange(components.startIndex..., in: components)).reversed() {
            result.replaceCharacters(in: match.range, with: result.substring(with: match.range).uppercased())
        }
        return String(result)
    }
}
