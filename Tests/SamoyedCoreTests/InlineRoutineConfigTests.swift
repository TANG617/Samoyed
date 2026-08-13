import Foundation
import XCTest
@testable import SamoyedCore

final class InlineRoutineConfigTests: XCTestCase {
    func testDecoderRestoresUTF8YAMLAndFeedsExistingValidator() throws {
        let yaml = """
        version: 1
        kind: day_blocks
        source_date: 2026-08-13
        blocks:
          - title: "午餐与午休"
            timing:
              type: absolute
              start: "12:00"
              end: "13:30"
            tasks:
              - title: "去吃午餐"
                completed: false
        """
        let payload = base64URL(Data(yaml.utf8))

        let decoded = try SamoyedInlineRoutineConfigDecoder().decode(
            version: 1,
            payload: payload
        )
        let summary = try SamoyedPortableDayBlocks.summary(fromYAML: decoded)

        XCTAssertEqual(decoded, yaml)
        XCTAssertEqual(summary.baseBlockCount, 1)
        XCTAssertEqual(summary.taskCount, 1)
    }

    func testDecoderRejectsUnsupportedVersion() throws {
        let payload = base64URL(Data("version: 1".utf8))

        XCTAssertThrowsError(
            try SamoyedInlineRoutineConfigDecoder().decode(version: 2, payload: payload)
        ) { error in
            XCTAssertEqual(error as? InlineRoutineConfigError, .unsupportedVersion(2))
        }
    }

    func testDecoderRejectsEmptyPayload() {
        XCTAssertThrowsError(
            try SamoyedInlineRoutineConfigDecoder().decode(version: 1, payload: "")
        ) { error in
            XCTAssertEqual(error as? InlineRoutineConfigError, .emptyPayload)
        }
    }

    func testDecoderRejectsInvalidBase64URL() {
        XCTAssertThrowsError(
            try SamoyedInlineRoutineConfigDecoder().decode(version: 1, payload: "a+b/c=")
        ) { error in
            XCTAssertEqual(error as? InlineRoutineConfigError, .invalidBase64URL)
        }

        XCTAssertThrowsError(
            try SamoyedInlineRoutineConfigDecoder().decode(version: 1, payload: "a")
        ) { error in
            XCTAssertEqual(error as? InlineRoutineConfigError, .invalidBase64URL)
        }
    }

    func testDecoderRejectsPayloadLargerThanConfiguredLimit() {
        let payload = base64URL(Data("12345".utf8))

        XCTAssertThrowsError(
            try SamoyedInlineRoutineConfigDecoder(maximumBytes: 4)
                .decode(version: 1, payload: payload)
        ) { error in
            XCTAssertEqual(
                error as? InlineRoutineConfigError,
                .payloadTooLarge(maximumBytes: 4)
            )
        }
    }

    func testDecoderRejectsNonUTF8Data() {
        let payload = base64URL(Data([0xFF]))

        XCTAssertThrowsError(
            try SamoyedInlineRoutineConfigDecoder().decode(version: 1, payload: payload)
        ) { error in
            XCTAssertEqual(error as? InlineRoutineConfigError, .invalidUTF8)
        }
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
