import XCTest
@testable import CheckpointAlerts

/// Parser tests for the official THP monthly PDF (tn.gov), in the shape its
/// text extracts: district sections, a DATE / COUNTY / LOCATION / TYPE
/// header, one row per checkpoint, with locations that wrap across lines.
/// Ported from the Android app's TennesseeSourceTest.
final class TennesseeSourceTests: XCTestCase {

    private let source = TennesseeSource()

    private func pdfDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d/yyyy"
        return f.string(from: date)
    }

    private func daysFromToday(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: Date())!
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day))!
    }

    private func pdfText(_ lines: String...) -> String {
        "TENNESSEE HIGHWAY PATROL CHECKPOINT ENFORCEMENT\n\n"
            + "KNOXVILLE DISTRICT 1\n"
            + "DATE       COUNTY                   LOCATION                          TYPE\n"
            + lines.joined(separator: "\n")
    }

    func testParsesThpPdfRows() {
        let text = pdfText(
            "\(pdfDate(daysFromToday(1)))    Sevier   Collier Drive @ Rainbow Road                     Sobriety",
            "\(pdfDate(daysFromToday(1)))    Jefferson   Sr 113 NEAR NINA ROAD                       Sobriety",
            "\(pdfDate(daysFromToday(1)))    Knox     Cherokee Trail @ Cherokee Bluff                  Sobreity",
            "\(pdfDate(daysFromToday(3)))    McNairy   SR 22 at SR 69                                DL",
            "\(pdfDate(daysFromToday(1)))    Hardeman   SR 18N @ 30MM                              seat belt",
            "Todd Levee Rd. South (North of",
            "\(pdfDate(daysFromToday(2)))    Crockett   Madison Co. Line)                          Sobriety",
            "State Route 62 near the 10 mm (just",
            "\(pdfDate(daysFromToday(2)))    Putnam                                                 Sobriety",
            "west of Fentress County)",
            "\(pdfDate(daysFromToday(2)))    Gibson   North of Madison Co Line                      Sobriety",
            // Duplicate of the Sevier row, must be deduped.
            "\(pdfDate(daysFromToday(1)))    Sevier   Collier Drive @ Rainbow Road                     Sobriety"
        )
        let result = source.parsePdfText(text, sourceUrl: "https://example.test/thp.pdf")
        XCTAssertEqual(result.count, 7)

        let sevier = result.first { $0.county == "Sevier" }!
        XCTAssertEqual(sevier.location, "Collier Drive @ Rainbow Road")
        XCTAssertEqual(Checkpoint.dayString(sevier.date), Checkpoint.dayString(daysFromToday(1)))
        XCTAssertEqual(sevier.type, .sobriety)

        // The PDF's own "Sobreity" typo still reads as a sobriety checkpoint.
        let knox = result.first { $0.county == "Knox" }!
        XCTAssertEqual(knox.location, "Cherokee Trail @ Cherokee Bluff")
        XCTAssertEqual(knox.type, .sobriety)

        let license = result.first { $0.county == "McNairy" }!
        XCTAssertEqual(license.type, .license)

        // Wrapped locations reassemble from the fragments around the date line.
        let crockett = result.first { $0.county == "Crockett" }!
        XCTAssertEqual(crockett.location, "Todd Levee Rd. South (North of Madison Co. Line)")
        let putnam = result.first { $0.county == "Putnam" }!
        XCTAssertEqual(putnam.location, "State Route 62 near the 10 mm (just west of Fentress County)")

        // A county name inside the location must not win over the real county.
        let gibson = result.first { $0.location.contains("Madison Co Line") }!
        XCTAssertEqual(gibson.county, "Gibson")

        XCTAssertTrue(result.allSatisfy { $0.county != "Hardeman" })
        XCTAssertEqual(result.count, Set(result.map(\.id)).count)
    }

    func testParsesRealNovemberPdfText() {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "thp-november-2026", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            XCTFail("thp-november-2026.txt test resource missing")
            return
        }
        let result = source.parsePdfText(
            text, sourceUrl: "https://example.test/thp.pdf", today: day(2026, 11, 1))
        // 75 dated rows in the file, minus 3 seat-belt rows.
        XCTAssertEqual(result.count, 72)
        XCTAssertEqual(result.count, Set(result.map(\.id)).count)

        let sevier = result.first { $0.county == "Sevier" }!
        XCTAssertEqual(sevier.location, "Collier Drive @ Rainbow Road")
        XCTAssertEqual(Checkpoint.dayString(sevier.date), "2026-11-20")

        let crockett = result.first { $0.county == "Crockett" }!
        XCTAssertEqual(crockett.location, "Todd Levee Rd. South (North of Madison Co. Line)")
        XCTAssertEqual(result.filter { $0.type == .license }.count, 2)
        XCTAssertTrue(result.allSatisfy { !$0.location.lowercased().contains("seat") })
    }

    func testDropsPastDates() {
        let text = pdfText(
            "\(pdfDate(daysFromToday(-2)))    Knox     Some Road at Main Street                        Sobriety",
            "\(pdfDate(daysFromToday(5)))    Knox     Other Road at Elm Street                      Sobriety"
        )
        let result = source.parsePdfText(text, sourceUrl: "https://example.test/thp.pdf")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(Checkpoint.dayString(result[0].date), Checkpoint.dayString(daysFromToday(5)))
    }

    func testReturnsEmptyForUnparseablePages() {
        let result = source.parsePdfText(
            "Nothing here yet.", sourceUrl: "https://example.test/thp.pdf")
        XCTAssertTrue(result.isEmpty)
    }

    func testParsePdfBytesReturnsNilWhenPdfCannotBeRead() {
        // Bytes that are not a PDF at all: extraction fails, and the
        // caller must see nil ("couldn't read the PDF"), not an empty
        // list ("downloaded but no checkpoints parsed").
        let result = source.parsePdfBytes(
            Data("not a pdf".utf8), sourceUrl: "https://example.test/thp.pdf")
        XCTAssertNil(result)
    }

    func testCheckpointIdsAreStableAcrossParses() {
        let text = pdfText(
            "\(pdfDate(daysFromToday(1)))    Sevier   Collier Drive @ Rainbow Road                     Sobriety"
        )
        let first = source.parsePdfText(text, sourceUrl: "https://example.test/thp.pdf")
        let second = source.parsePdfText(text, sourceUrl: "https://example.test/thp.pdf")
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].id, second[0].id)
        XCTAssertTrue(first[0].id.hasPrefix("TN|Sevier|"))
    }

    func testJavaHashCodeMatchesJava() {
        // "hello".hashCode() in Java is 99162322; the checkpoint id suffix
        // must match the Android app exactly.
        XCTAssertEqual(javaHashCode("hello"), 9_916_322)
        XCTAssertEqual(javaHashCode(""), 0)
    }
}
