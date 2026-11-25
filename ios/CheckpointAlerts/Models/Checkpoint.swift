import Foundation

/// One publicly announced checkpoint. Only ever built from what a source
/// actually lists, the app never invents checkpoint data.
struct Checkpoint: Identifiable, Codable, Equatable {
    let id: String
    let stateCode: String
    let county: String
    let city: String
    let location: String
    /// Day-precision date, stored as "yyyy-MM-dd" in the JSON cache.
    let date: Date
    let type: CheckpointType
    let sourceUrl: String

    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var isTomorrow: Bool { Calendar.current.isDateInTomorrow(date) }

    enum CodingKeys: String, CodingKey {
        case id, county, city, location, date, type
        case stateCode = "state"
        case sourceUrlKey = "source"
    }

    init(
        id: String,
        stateCode: String,
        county: String,
        city: String = "",
        location: String,
        date: Date,
        type: CheckpointType,
        sourceUrl: String
    ) {
        self.id = id
        self.stateCode = stateCode
        self.county = county
        self.city = city
        self.location = location
        self.date = date
        self.type = type
        self.sourceUrl = sourceUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        stateCode = try c.decodeIfPresent(String.self, forKey: .stateCode) ?? "TN"
        county = try c.decode(String.self, forKey: .county)
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        location = try c.decode(String.self, forKey: .location)
        let dateString = try c.decode(String.self, forKey: .date)
        date = Checkpoint.dayFormatter.date(from: dateString) ?? Date()
        type = try c.decode(CheckpointType.self, forKey: .type)
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrlKey) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(stateCode, forKey: .stateCode)
        try c.encode(county, forKey: .county)
        try c.encode(city, forKey: .city)
        try c.encode(location, forKey: .location)
        try c.encode(Checkpoint.dayFormatter.string(from: date), forKey: .date)
        try c.encode(type, forKey: .type)
        try c.encode(sourceUrl, forKey: .sourceUrlKey)
    }

    /// "yyyy-MM-dd" in UTC, the same day string the Android cache uses.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

enum CheckpointType: String, Codable {
    case sobriety = "SOBRIETY"
    case license = "LICENSE"

    var label: String {
        switch self {
        case .sobriety: return "Sobriety"
        case .license: return "License"
        }
    }
}

/// Java/Kotlin String.hashCode(): h = 31*h + utf16 unit, wrapping Int32.
/// Used so checkpoint ids match the Android app exactly.
func javaHashCode(_ s: String) -> Int32 {
    var h: Int32 = 0
    for unit in s.utf16 {
        h = 31 &* h &+ Int32(unit)
    }
    return h
}

/// Start of day for a date, in the device calendar.
func startOfDay(_ date: Date) -> Date {
    Calendar.current.startOfDay(for: date)
}
