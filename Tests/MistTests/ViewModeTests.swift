import XCTest
@testable import Mist

final class ViewModeTests: XCTestCase {

    func testDefaultWhenNilIsPreview() {
        XCTAssertEqual(ViewMode.resolved(storedRaw: nil), .preview)
    }

    func testDefaultWhenEmptyOrInvalidIsPreview() {
        XCTAssertEqual(ViewMode.resolved(storedRaw: ""), .preview)
        XCTAssertEqual(ViewMode.resolved(storedRaw: "editor"), .preview)
        XCTAssertEqual(ViewMode.resolved(storedRaw: "PREVIEW"), .preview)
    }

    func testRestoresStoredRawValues() {
        XCTAssertEqual(ViewMode.resolved(storedRaw: "preview"), .preview)
        XCTAssertEqual(ViewMode.resolved(storedRaw: "split"), .split)
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(ViewMode.preview.rawValue, "preview")
        XCTAssertEqual(ViewMode.split.rawValue, "split")
    }
}
