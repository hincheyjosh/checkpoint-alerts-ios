import Foundation
import PDFKit

/// Tennessee checkpoint source, the official list only.
///
/// The Tennessee Highway Patrol publishes the full month's checkpoints as a
/// PDF on tn.gov (one file per month, every district, DATE / COUNTY /
/// LOCATION / TYPE rows). That is the ONLY source this app reads for
/// Tennessee. An earlier Android version also read aggregator sites that
/// republish the same announcements; the two copies worded each location
/// differently, so the same checkpoint showed up twice. One official source
/// means one entry per checkpoint.
///
/// PDF: https://www.tn.gov/content/dam/tn/safety/documents/thp-checkpoints/
///      {YYYY}/{MONTH}.pdf  (e.g. 2026/NOVEMBER.pdf)
/// The app fetches the current month and the next month, so checkpoints
/// announced early for next month already show up. A next-month file that
/// does not exist yet is normal and is skipped, not an error.
///
/// The PDF lists dates only, THP doesn't release times, so checkpoints
/// carry no time at all, and the app shows none.
/// Seat-belt enforcement rows are out of scope and are dropped; sobriety
/// and driver-license rows are kept. It only ever returns what the list
/// shows, never invented data. If every fetch fails, fetch() throws and
/// the app keeps showing the last saved data with a "couldn't refresh"
/// state.
///
/// Ported from the Android app's TennesseeSource.kt, same logic, same
/// parser, same ids (including Java String.hashCode for the id suffix).
final class TennesseeSource {

    let stateCode = "TN"
    let stateName = "Tennessee"

    private let baseUrl =
        "https://www.tn.gov/content/dam/tn/safety/documents/thp-checkpoints"

    // tn.gov's edge blocks bare automated fetches (HTTP 403 / dropped
    // connections). The Android app stayed empty on the phone until the
    // request sent what a current browser sends, and retries once on a
    // transient failure. Same headers here, with a current Safari on
    // iPhone user agent.
    private let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 " +
        "Mobile/15E148 Safari/604.1"

    /// Last download failure, for the error fetch() throws.
    private var lastDownloadFailure: String?

    func fetch() async throws -> [Checkpoint] {
        var found: [Checkpoint] = []
        var anyOk = false
        var lastFailure: String?
        let now = Date()
        let calendar = Calendar.current
        let thisMonth = calendar.dateComponents([.year, .month], from: now)
        for monthOffset in [0, 1] {
            guard let monthDate = calendar.date(
                byAdding: .month, value: monthOffset,
                to: calendar.date(from: thisMonth) ?? now
            ) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: monthDate)
            guard let pdf = await downloadPdf(year: comps.year ?? 0, month: comps.month ?? 0) else {
                lastFailure = lastDownloadFailure
                continue
            }
            guard let parsed = parsePdfBytes(pdf.data, sourceUrl: pdf.url) else {
                // The bytes downloaded but the PDF could not be read,
                // a different failure from a readable PDF with no rows.
                lastFailure = "couldn't read the PDF"
                continue
            }
            if parsed.isEmpty {
                lastFailure = "downloaded but no checkpoints parsed"
                continue
            }
            anyOk = true
            found += parsed
        }
        if !anyOk && found.isEmpty {
            throw TennesseeSourceError.loadFailed(
                lastFailure.map { "Could not load the THP checkpoint list (\($0))" }
                    ?? "Could not load the THP checkpoint list"
            )
        }
        return dedupSorted(found)
    }

    private struct PdfDownload {
        let data: Data
        let url: String
    }

    private func downloadPdf(year: Int, month: Int) async -> PdfDownload? {
        let monthName = Self.monthName(month)
        let urls = [
            "\(baseUrl)/\(year)/\(monthName).pdf",
            "\(baseUrl)/archived-\(year)/\(monthName).pdf",
        ]
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            if let data = await downloadUrl(url) {
                return PdfDownload(data: data, url: urlString)
            }
        }
        return nil
    }

    /// Download one URL, sending the headers a current browser sends.
    /// Retries once on a transient failure (dropped connection, 5xx, 403);
    /// a 404 is final, the file simply isn't published yet.
    /// Returns the bytes, or nil.
    func downloadUrl(_ url: URL) async -> Data? {
        var lastError: String?
        for attempt in 0...1 {
            do {
                var request = URLRequest(url: url, timeoutInterval: 25)
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(
                    "text/html,application/xhtml+xml,application/xml;q=0.9," +
                    "image/avif,image/webp,image/apng,*/*;q=0.8," +
                    "application/signed-exchange;v=b3;q=0.7",
                    forHTTPHeaderField: "Accept"
                )
                request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = "no response"
                    continue
                }
                if http.statusCode == 200 {
                    if data.count > 1000 && isPdf(data) { return data }
                    lastDownloadFailure = "not a PDF"
                    return nil
                }
                lastError = "HTTP \(http.statusCode)"
                // 404 means the file isn't published yet, no point retrying.
                if http.statusCode == 404 { break }
            } catch {
                lastError = String(describing: type(of: error))
            }
            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        lastDownloadFailure = lastError
        return nil
    }

    private func isPdf(_ data: Data) -> Bool {
        data.count >= 4 && data[0] == 0x25 && data[1] == 0x50
            && data[2] == 0x44 && data[3] == 0x46
    }

    /// Parse a downloaded THP PDF. Returns nil when the PDF itself could
    /// not be read, and an empty list when the text extracted fine but
    /// yielded no checkpoint rows.
    func parsePdfBytes(_ data: Data, sourceUrl: String, today: Date = Date()) -> [Checkpoint]? {
        guard let doc = PDFDocument(data: data) else { return nil }
        var text = ""
        for i in 0..<doc.pageCount {
            if let pageText = doc.page(at: i)?.string {
                text += pageText + "\n"
            }
        }
        return parsePdfText(text, sourceUrl: sourceUrl, today: today)
    }

    /// Parse the extracted text of a THP monthly PDF.
    func parsePdfText(_ text: String, sourceUrl: String, today: Date = Date()) -> [Checkpoint] {
        let todayStart = startOfDay(today)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !$0.contains("CHECKPOINT ENFORCEMENT") }
            .filter { Self.districtHeaderRegex.firstMatch(in: $0) == nil }
            .filter { !Self.columnWords.contains($0) }
            .filter { !($0.contains("DATE") && $0.contains("COUNTY") && $0.contains("LOCATION")) }

        // Group lines into records. Each record starts at a line carrying a
        // date; the location text can wrap onto lines above and below that
        // line. A wrapped fragment belongs to the record below it when the
        // previous record's location reads complete, and to the record above
        // it when that location ends mid-phrase (open paren, trailing "of",
        // "just", ...). That is how the official PDF lays its wrapped rows
        // out, verified against the real November 2026 file.
        var records: [RawRecord] = []
        var cur: RawRecord?
        var pending: [String] = []
        for line in lines {
            if let dateMatch = Self.dateRegex.firstMatch(in: line) {
                if let finished = cur { records.append(finished) }
                let nsLine = line as NSString
                let dateRange = dateMatch.range
                let dateText = nsLine.substring(with: dateRange)
                let restStart = dateRange.location + dateRange.length
                let dateLineRest = restStart < nsLine.length
                    ? nsLine.substring(from: restStart).trimmingCharacters(in: .whitespaces)
                    : ""
                cur = RawRecord(
                    dateText: dateText,
                    preFragments: pending,
                    dateLineRest: dateLineRest,
                    postFragments: []
                )
                pending = []
            } else if cur == nil {
                pending.append(line)
            } else {
                var current = cur!
                let locSoFar = (current.preFragments
                    + [lineLocation(current.dateLineRest)]
                    + current.postFragments)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if Self.locationIncomplete(locSoFar) {
                    current.postFragments.append(line)
                } else {
                    pending.append(line)
                }
                cur = current
            }
        }
        if let finished = cur { records.append(finished) }

        var out: [Checkpoint] = []
        for rec in records {
            if let c = parseRecord(rec, sourceUrl: sourceUrl, todayStart: todayStart) {
                out.append(c)
            }
        }
        return dedupSorted(out)
    }

    private func parseRecord(
        _ rec: RawRecord,
        sourceUrl: String,
        todayStart: Date
    ) -> Checkpoint? {
        guard let date = Self.parsePdfDate(rec.dateText) else { return nil }
        if date < todayStart { return nil }
        guard let countyMatch = matchCounty(rec.dateLineRest) else { return nil }
        let county = countyMatch.name
        let fullText = (rec.preFragments + [rec.dateLineRest] + rec.postFragments)
            .joined(separator: " ")
        let lower = fullText.lowercased()
        // Seat-belt enforcement is out of scope for this app.
        if lower.contains("seat belt") || lower.contains("seatbelt") { return nil }
        let type: CheckpointType = Self.licenseRegex.firstMatch(in: fullText) != nil
            ? .license : .sobriety
        let joined = (rec.preFragments + [lineLocation(rec.dateLineRest)] + rec.postFragments)
            .map { Self.cleanLocation($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let location = Self.cleanLocation(joined)
        guard location.count >= 4 else { return nil }
        let normalized = location.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return Checkpoint(
            id: "TN|\(county)|\(Checkpoint.dayString(date))|\(javaHashCode(normalized))",
            stateCode: "TN",
            county: county,
            city: "",
            location: location,
            date: date,
            type: type,
            sourceUrl: sourceUrl
        )
    }

    /// A date line's rest (everything after the date) minus its county and
    /// type words, i.e. just the location text on that line, if any.
    private func lineLocation(_ rest: String) -> String {
        var s = rest as NSString
        if let county = matchCounty(rest) {
            s = s.replacingCharacters(in: county.range, with: "") as NSString
        }
        var result = Self.typeRegex.stringByReplacingMatches(
            in: s as String, range: NSRange(location: 0, length: s.length), withTemplate: "")
        result = result
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        return result
    }

    private static func cleanLocation(_ raw: String) -> String {
        var s = typeRegex.stringByReplacingMatches(
            in: raw, range: NSRange(location: 0, length: (raw as NSString).length),
            withTemplate: "")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: "( ", with: "(")
            .replacingOccurrences(of: " )", with: ")")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        return s
    }

    /// True when a location string ends mid-phrase, so the next line is a
    /// continuation of it rather than a new row's text.
    private static func locationIncomplete(_ loc: String) -> Bool {
        let t = loc.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return false }
        if t.filter({ $0 == "(" }).count > t.filter({ $0 == ")" }).count { return true }
        let last = t.split(separator: " ").last.map(String.init) ?? ""
        let cleaned = last.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,):"))
        return Self.continueWords.contains(cleaned)
    }

    /// Earliest whole-word county name in [text], with its range.
    private func matchCounty(_ text: String) -> (name: String, range: NSRange)? {
        var best: (name: String, range: NSRange)?
        for name in TnCounties.all {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = regex.firstMatch(
                      in: text, range: NSRange(location: 0, length: (text as NSString).length))
            else { continue }
            if best == nil || m.range.location < best!.range.location {
                best = (name, m.range)
            }
        }
        return best
    }

    private func dedupSorted(_ list: [Checkpoint]) -> [Checkpoint] {
        var seen = Set<String>()
        var out: [Checkpoint] = []
        for c in list where seen.insert(c.id).inserted {
            out.append(c)
        }
        return out.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.county != $1.county { return $0.county < $1.county }
            return $0.location < $1.location
        }
    }

    private static func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        var comps = DateComponents()
        comps.year = 2026
        comps.month = month
        comps.day = 1
        let date = Calendar(identifier: .gregorian).date(from: comps) ?? Date()
        return formatter.string(from: date).uppercased()
    }

    // MARK: - Regexes

    private static let dateRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "(\\d{1,2}/\\d{1,2}/\\d{4})")
    }()

    /// Any type word the PDF prints: sobriety (including the PDF's own
    /// "Sobreity" typo), DUI/DWI, driver license / DL, seat belt.
    private static let typeRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: "\\b(seat belt|seatbelt|sobreity|sobriety|dui|dwi|driver license|license|dl)\\b",
            options: .caseInsensitive)
    }()

    private static let licenseRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: "\\b(dl|driver license|license)\\b",
            options: .caseInsensitive)
    }()

    private static let districtHeaderRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^[A-Z ]+DISTRICT \\d+$")
    }()

    private static let columnWords: Set<String> = ["DATE", "COUNTY", "LOCATION", "TYPE"]

    private static let continueWords: Set<String> = [
        "of", "near", "at", "just", "the", "and", "or", "a", "an",
        "to", "for", "with", "by", "from", "in", "on", "(", "-", ",", "&", "@",
    ]

    private static let pdfDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "M/d/yyyy"
        return f
    }()

    /// Parse dates like "11/20/2026", normalized to start of day.
    static func parsePdfDate(_ raw: String) -> Date? {
        guard let d = pdfDateFormatter.date(from: raw.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return startOfDay(d)
    }
}

enum TennesseeSourceError: Error {
    case loadFailed(String)
}

/// One date-anchored group of lines from the PDF text, before it is
/// interpreted as a checkpoint.
private struct RawRecord {
    var dateText: String
    var preFragments: [String]
    var dateLineRest: String
    var postFragments: [String]
}

private extension NSRegularExpression {
    func firstMatch(in string: String) -> NSTextCheckingResult? {
        firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
    }
}
