import Testing
import Foundation
@testable import vreader

@Suite("TapZoneConfig")
struct TapZoneConfigTests {
    @Test func defaultZones_leftPrevPage_centerToggle_rightNextPage() {
        let config = TapZoneConfig.default
        #expect(config.leftAction == .previousPage)
        #expect(config.centerAction == .toggleChrome)
        #expect(config.rightAction == .nextPage)
    }
    @Test func tapInLeftZone() { #expect(TapZoneConfig.zone(atX: 100, totalWidth: 1000) == .left) }
    @Test func tapInCenterZone() { #expect(TapZoneConfig.zone(atX: 500, totalWidth: 1000) == .center) }
    @Test func tapInRightZone() { #expect(TapZoneConfig.zone(atX: 800, totalWidth: 1000) == .right) }
    @Test func leftEdge() { #expect(TapZoneConfig.zone(atX: 0, totalWidth: 1000) == .left) }
    @Test func rightEdge() { #expect(TapZoneConfig.zone(atX: 1000, totalWidth: 1000) == .right) }
    @Test func centerExact() { #expect(TapZoneConfig.zone(atX: 500, totalWidth: 1000) == .center) }
    @Test func leftBoundary() { #expect(TapZoneConfig.zone(atX: 330, totalWidth: 1000) == .left) }
    @Test func pastLeftBoundary() { #expect(TapZoneConfig.zone(atX: 334, totalWidth: 1000) == .center) }
    @Test func rightBoundary() { #expect(TapZoneConfig.zone(atX: 660, totalWidth: 1000) == .center) }
    @Test func pastRightBoundary() { #expect(TapZoneConfig.zone(atX: 667, totalWidth: 1000) == .right) }
    @Test func zeroWidth() { #expect(TapZoneConfig.zone(atX: 0, totalWidth: 0) == .center) }
    @Test func negativeX() { #expect(TapZoneConfig.zone(atX: -10, totalWidth: 1000) == .left) }
    @Test func xExceedsWidth() { #expect(TapZoneConfig.zone(atX: 1500, totalWidth: 1000) == .right) }
    @Test func actionForZone() {
        let config = TapZoneConfig.default
        #expect(config.action(for: .left) == .previousPage)
        #expect(config.action(for: .center) == .toggleChrome)
        #expect(config.action(for: .right) == .nextPage)
    }
    @Test func codableRoundTrip() throws {
        let config = TapZoneConfig(leftAction: .nextPage, centerAction: .none, rightAction: .toggleChrome)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TapZoneConfig.self, from: data)
        #expect(decoded == config)
    }
    @Test func defaultCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(TapZoneConfig.default)
        let decoded = try JSONDecoder().decode(TapZoneConfig.self, from: data)
        #expect(decoded == .default)
    }
    @Test func customMapping() {
        var config = TapZoneConfig.default
        config.leftAction = .toggleChrome
        config.centerAction = .none
        config.rightAction = .previousPage
        #expect(config.action(for: .left) == .toggleChrome)
        #expect(config.action(for: .center) == .none)
        #expect(config.action(for: .right) == .previousPage)
    }
    @Test func allActionsAssignable() {
        for action in TapAction.allCases {
            var c = TapZoneConfig.default
            c.leftAction = action; #expect(c.action(for: .left) == action)
            c.centerAction = action; #expect(c.action(for: .center) == action)
            c.rightAction = action; #expect(c.action(for: .right) == action)
        }
    }
    @Test func zoneRawValues() {
        #expect(TapZone.left.rawValue == "left")
        #expect(TapZone.center.rawValue == "center")
        #expect(TapZone.right.rawValue == "right")
    }
    @Test func actionRawValues() {
        #expect(TapAction.previousPage.rawValue == "previousPage")
        #expect(TapAction.nextPage.rawValue == "nextPage")
        #expect(TapAction.toggleChrome.rawValue == "toggleChrome")
        #expect(TapAction.none.rawValue == "none")
    }
    @Test func actionAllCases() { #expect(TapAction.allCases.count == 4) }
}

@Suite("TapZoneStore")
@MainActor
struct TapZoneStoreTests {
    @Test func defaultConfig() {
        let suiteName = "TapZoneStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let store = TapZoneStore(defaults: defaults)
        #expect(store.config == .default)
        defaults.removePersistentDomain(forName: suiteName)
    }
    @Test func persistsCustomConfig() {
        let suiteName = "TapZoneStoreTests-p-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let store1 = TapZoneStore(defaults: defaults)
        store1.config = TapZoneConfig(leftAction: .toggleChrome, centerAction: .none, rightAction: .previousPage)
        let store2 = TapZoneStore(defaults: defaults)
        #expect(store2.config.leftAction == .toggleChrome)
        #expect(store2.config.centerAction == .none)
        #expect(store2.config.rightAction == .previousPage)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
