// Purpose: Ready-seam isolation for open_book target delivery in WI-6.

import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-6 — pending book navigation ready seam")
struct AIPendingBookNavigationStoreTests {
    @Test("a target is delivered only to the newly claimed reader token")
    func exactTokenClaimsTarget() async {
        let fingerprint = WI6Fixtures.fingerprint("9", format: .epub)
        let locator = WI6Fixtures.locator(
            fingerprint: fingerprint, href: "chapter.xhtml"
        )
        let oldToken = UUID(), newToken = UUID()
        let store = AIPendingBookNavigationStore()
        await store.set(locator, for: fingerprint.canonicalKey)
        await store.claim(
            fingerprintKey: fingerprint.canonicalKey, readerToken: newToken
        )

        #expect(await store.take(
            for: fingerprint.canonicalKey, readerToken: oldToken
        ) == nil)
        #expect(await store.take(
            for: fingerprint.canonicalKey, readerToken: newToken
        ) == locator)
    }

    @Test("the claimed target is one-shot and duplicate delivery is harmless")
    func targetIsOneShot() async {
        let fingerprint = WI6Fixtures.fingerprint("0", format: .pdf)
        let locator = WI6Fixtures.locator(fingerprint: fingerprint, page: 4)
        let token = UUID()
        let store = AIPendingBookNavigationStore()
        await store.set(locator, for: fingerprint.canonicalKey)
        await store.claim(fingerprintKey: fingerprint.canonicalKey, readerToken: token)

        #expect(await store.take(
            for: fingerprint.canonicalKey, readerToken: token
        ) == locator)
        #expect(await store.take(
            for: fingerprint.canonicalKey, readerToken: token
        ) == nil)
    }
}
