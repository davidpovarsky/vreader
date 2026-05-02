// Purpose: Tests for DebugCommand parser — URL grammar for the vreader-debug://
// scheme used by feature #44 DebugBridge. Pure value-type parsing, no OS deps.

#if DEBUG

import XCTest
@testable import vreader

final class DebugCommandTests: XCTestCase {

    // MARK: - reset

    func test_parse_reset_returnsResetCommand() throws {
        let url = URL(string: "vreader-debug://reset")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .reset)
    }

    func test_parse_resetWithTrailingSlash_returnsResetCommand() throws {
        let url = URL(string: "vreader-debug://reset/")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .reset)
    }

    // MARK: - seed

    func test_parse_seedWithFixture_returnsSeed() throws {
        let url = URL(string: "vreader-debug://seed?fixture=alice")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .seed(fixture: "alice"))
    }

    func test_parse_seedMissingFixture_throwsMissingParam() {
        let url = URL(string: "vreader-debug://seed")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "fixture")
        }
    }

    func test_parse_seedEmptyFixtureValue_throwsMissingParam() {
        let url = URL(string: "vreader-debug://seed?fixture=")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "fixture")
        }
    }

    // MARK: - open

    func test_parse_openWithBookIdAndCFI_returnsOpen() throws {
        let bookId = "550e8400-e29b-41d4-a716-446655440000"
        let cfi = "epubcfi(/6/4!/4/1:0)"
        let encodedCFI = cfi.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "vreader-debug://open?bookId=\(bookId)&cfi=\(encodedCFI)")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .open(bookId: bookId, position: cfi))
    }

    func test_parse_openWithBookIdOnly_returnsOpenWithNilPosition() throws {
        let bookId = "550e8400-e29b-41d4-a716-446655440000"
        let url = URL(string: "vreader-debug://open?bookId=\(bookId)")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .open(bookId: bookId, position: nil))
    }

    func test_parse_openMissingBookId_throwsMissingParam() {
        let url = URL(string: "vreader-debug://open")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "bookId")
        }
    }

    // MARK: - theme

    func test_parse_themeDarkWithFontSize_returnsTheme() throws {
        let url = URL(string: "vreader-debug://theme?mode=dark&fontSize=18")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .theme(mode: .dark, fontSize: 18))
    }

    func test_parse_themeLightModeOnly_returnsThemeWithNilFontSize() throws {
        let url = URL(string: "vreader-debug://theme?mode=light")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .theme(mode: .light, fontSize: nil))
    }

    func test_parse_themeUnknownMode_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://theme?mode=neon")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "mode")
        }
    }

    func test_parse_themeNonNumericFontSize_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://theme?mode=dark&fontSize=huge")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "fontSize")
        }
    }

    // MARK: - settle

    func test_parse_settleWithToken_returnsSettle() throws {
        let url = URL(string: "vreader-debug://settle?token=abc-123")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .settle(token: "abc-123"))
    }

    func test_parse_settleMissingToken_throwsMissingParam() {
        let url = URL(string: "vreader-debug://settle")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "token")
        }
    }

    // MARK: - snapshot

    func test_parse_snapshotWithDest_returnsSnapshot() throws {
        let url = URL(string: "vreader-debug://snapshot?dest=state.json")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .snapshot(dest: "state.json"))
    }

    func test_parse_snapshotMissingDest_throwsMissingParam() {
        let url = URL(string: "vreader-debug://snapshot")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "dest")
        }
    }

    // MARK: - eval

    func test_parse_evalWithBridgeAndBase64JS_returnsEvalWithDecodedJS() throws {
        let js = "document.querySelectorAll('.foliate-highlight').length"
        let encoded = Data(js.utf8).base64EncodedString()
        let urlEncoded = encoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "vreader-debug://eval?bridge=foliate&js=\(urlEncoded)")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .eval(bridge: "foliate", js: js))
    }

    func test_parse_evalInvalidBase64_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://eval?bridge=foliate&js=not-valid-base64!!!")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "js")
        }
    }

    func test_parse_evalMissingBridge_throwsMissingParam() {
        let js = Data("foo".utf8).base64EncodedString()
        let url = URL(string: "vreader-debug://eval?js=\(js)")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "bridge")
        }
    }

    // MARK: - scheme + host validation

    func test_parse_wrongScheme_throwsInvalidScheme() {
        let url = URL(string: "https://reset")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidScheme = error else {
                XCTFail("expected invalidScheme, got \(error)")
                return
            }
        }
    }

    func test_parse_unknownHost_throwsUnknownCommand() {
        let url = URL(string: "vreader-debug://teleport")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.unknownCommand(let name) = error else {
                XCTFail("expected unknownCommand, got \(error)")
                return
            }
            XCTAssertEqual(name, "teleport")
        }
    }

    func test_parse_missingHost_throwsUnknownCommand() {
        let url = URL(string: "vreader-debug://")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.unknownCommand = error else {
                XCTFail("expected unknownCommand, got \(error)")
                return
            }
        }
    }
}

#endif
