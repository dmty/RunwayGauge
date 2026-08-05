import Security
import Testing
import UsageCore
@testable import RunwayGauge

struct KeychainDiscoveryTests {
    @Test("attribute results map to descriptors without requesting secret data")
    func mapsAttributeResults() {
        let rows: [[CFString: Any]] = [
            [
                kSecAttrService: "Claude Code-credentials",
                kSecAttrAccount: "person@example.com",
            ],
            [
                kSecAttrService: "Claude Code-credentials-work",
            ],
            [
                kSecAttrAccount: "missing-service",
            ],
        ]

        let descriptors = KeychainDiscovery.descriptors(from: rows)

        #expect(descriptors == [
            KeychainItemDescriptor(
                service: "Claude Code-credentials",
                account: "person@example.com"
            ),
            KeychainItemDescriptor(service: "Claude Code-credentials-work"),
        ])
    }

    @Test("discovery query requests attributes but never secret data")
    func queryDoesNotRequestSecretData() {
        let query = KeychainDiscovery.discoveryQuery

        #expect(query[kSecClass] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecMatchLimit] as? String == kSecMatchLimitAll as String)
        #expect(query[kSecReturnAttributes] as? Bool == true)
        #expect(query[kSecReturnData] as? Bool == false)
    }
}
