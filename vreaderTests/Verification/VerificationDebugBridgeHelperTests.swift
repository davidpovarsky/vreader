// Purpose: Specification tests for the vreader-debug:// URL schema used by
// VerificationDebugBridgeHelper (feature #45 WI-1). Tests document the expected
// URL format for each command and verify edge cases: empty fixture name, special
// characters in token/dest, query-item encoding round-trips.
//
// These are specification tests — they prove the URL contract is stable and
// serve as the canonical reference for VerificationDebugBridgeHelper's
// URL construction logic.

#if DEBUG

import Testing
import Foundation
@testable import vreader

@Suite("VerificationDebugBridgeHelper URL spec")
struct VerificationDebugBridgeHelperSpec {

    // MARK: - reset

    @Test func resetURL_hasCorrectScheme() {
        let url = URL(string: "vreader-debug://reset")!
        #expect(url.scheme == "vreader-debug")
        #expect(url.host() == "reset")
    }

    @Test func resetURL_hasNoQueryItems() {
        let components = URLComponents(string: "vreader-debug://reset")!
        #expect(components.queryItems == nil || components.queryItems!.isEmpty)
    }

    // MARK: - seed

    @Test func seedURL_encodesFixtureName() throws {
        var c = URLComponents()
        c.scheme = "vreader-debug"
        c.host = "seed"
        c.queryItems = [URLQueryItem(name: "fixture", value: "mini-epub3")]
        let url = try #require(c.url)
        let decoded = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems?.first(where: { $0.name == "fixture" })?.value
        #expect(decoded == "mini-epub3")
    }

    @Test func seedURL_encodesFixtureName_withHyphen() throws {
        var c = URLComponents()
        c.scheme = "vreader-debug"
        c.host = "seed"
        c.queryItems = [URLQueryItem(name: "fixture", value: "war-and-peace")]
        let url = try #require(c.url)
        let decoded = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems?.first(where: { $0.name == "fixture" })?.value
        #expect(decoded == "war-and-peace")
    }

    @Test func seedURL_emptyFixtureName_stillProducesURL() throws {
        var c = URLComponents()
        c.scheme = "vreader-debug"
        c.host = "seed"
        c.queryItems = [URLQueryItem(name: "fixture", value: "")]
        let url = try #require(c.url)
        let decoded = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems?.first(where: { $0.name == "fixture" })?.value
        #expect(decoded == "")
    }

    // MARK: - settle

    @Test func settleURL_encodesToken() throws {
        var c = URLComponents()
        c.scheme = "vreader-debug"
        c.host = "settle"
        c.queryItems = [URLQueryItem(name: "token", value: "test-settle-1")]
        let url = try #require(c.url)
        let decoded = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems?.first(where: { $0.name == "token" })?.value
        #expect(decoded == "test-settle-1")
    }

    @Test(arguments: [
        "simple",
        "with-hyphen",
        "with_underscore",
        "CamelCase",
        "with spaces",
        "unicode-café",
    ])
    func settleURL_roundTripsToken(token: String) throws {
        var c = URLComponents()
        c.scheme = "vreader-debug"
        c.host = "settle"
        c.queryItems = [URLQueryItem(name: "token", value: token)]
        let url = try #require(c.url)
        let decoded = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems?.first(where: { $0.name == "token" })?.value
        #expect(decoded == token, "token '\(token)' must survive URL round-trip")
    }

    // MARK: - snapshot

    @Test func snapshotURL_encodesDest() throws {
        var c = URLComponents()
        c.scheme = "vreader-debug"
        c.host = "snapshot"
        c.queryItems = [URLQueryItem(name: "dest", value: "verify-snap.json")]
        let url = try #require(c.url)
        let decoded = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems?.first(where: { $0.name == "dest" })?.value
        #expect(decoded == "verify-snap.json")
    }

    @Test func snapshotURL_encodesDestWithPath() throws {
        var c = URLComponents()
        c.scheme = "vreader-debug"
        c.host = "snapshot"
        c.queryItems = [URLQueryItem(name: "dest", value: "sub/verify.json")]
        let url = try #require(c.url)
        let decoded = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems?.first(where: { $0.name == "dest" })?.value
        #expect(decoded == "sub/verify.json")
    }

    // MARK: - known fixture names

    @Test func fixtureNamesInCatalog_containsMiniEpub3() {
        let names = DebugFixtureCatalog.all().map { $0.name }
        #expect(names.contains("mini-epub3"),
                "mini-epub3 fixture must be in DebugFixtureCatalog for Feature11 tests")
    }

    @Test func fixtureNamesInCatalog_containsWarAndPeace() {
        let names = DebugFixtureCatalog.all().map { $0.name }
        #expect(names.contains("war-and-peace"),
                "war-and-peace fixture must be in DebugFixtureCatalog for Feature23 tests")
    }
}

#endif
