import Foundation
import Testing
@testable import UsageCore

private func json(_ s: String) -> Data { Data(s.utf8) }

private func tempDir() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "account-store-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func sampleRegistry(sourceKind: SourceKind = .claudeOAuth) -> AccountRegistry {
    AccountRegistry(
        schema: 1,
        revision: 7,
        prefs: AccountPreferences(
            selectedAccountId: "acc_test",
            rotateEnabled: false,
            rotateIntervalSec: 900,
            rotationAnchorAt: 1_785_888_000
        ),
        accounts: [
            Account(
                id: "acc_test",
                label: "Claude",
                sourceKind: sourceKind,
                pinned: true,
                credentials: AccountCredentials(
                    configDir: "~/.claude",
                    keychain: KeychainReference(
                        service: "Claude Code-credentials",
                        account: "user@example.com"
                    ),
                    nonSecretFields: [:]
                )
            )
        ]
    )
}

@Test("complete schema-1 round trip")
func completeSchema1RoundTrip() throws {
    let registry = sampleRegistry()
    let data = try AccountRegistry.encode(registry)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let accounts = try #require(object["accounts"] as? [[String: Any]])
    let encodedSourceKind = try #require(accounts.first?["sourceKind"])
    #expect(encodedSourceKind is String)
    #expect(encodedSourceKind as? String == "claude-oauth")

    let decoded = try AccountRegistry.decode(data)
    #expect(decoded == registry)

    let dir = try tempDir()
    let url = dir.appending(path: "accounts.json")
    try AccountStore.save(registry, to: url)
    let loaded = try AccountStore.load(from: url)
    #expect(loaded == registry)
}

@Test("missing preference keys decode with defaults")
func missingPreferenceDefaults() throws {
    let registry = try AccountRegistry.decode(json("""
    {"schema":1,"revision":0,"prefs":{},"accounts":[]}
    """))
    #expect(registry.prefs.selectedAccountId == nil)
    #expect(registry.prefs.rotateEnabled == false)
    #expect(registry.prefs.rotateIntervalSec == 900)
    #expect(registry.prefs.rotationAnchorAt == nil)
}

@Test("missing nonSecretFields decodes as empty map")
func missingNonSecretFieldsDefault() throws {
    let registry = try AccountRegistry.decode(json("""
    {"schema":1,"revision":0,"prefs":{},"accounts":[
      {"id":"acc_x","label":"X","sourceKind":"claude-oauth","pinned":true,
       "credentials":{"configDir":"~/.claude"}}
    ]}
    """))
    #expect(registry.accounts[0].credentials.nonSecretFields == [:])
}

@Test("rejects an unsupported schema")
func rejectsUnknownSchema() {
    let data = json("""
    {"schema":2,"revision":0,"prefs":{},"accounts":[]}
    """)
    #expect(throws: AccountDecodeError.unsupportedSchema(2)) {
        try AccountRegistry.decode(data)
    }
}

@Test("rejects malformed json")
func rejectsMalformedJSON() {
    #expect(throws: AccountDecodeError.malformed) {
        try AccountRegistry.decode(json("{not json"))
    }
}

@Test("missing file is distinguished from malformed registry")
func missingVsMalformedRegistry() throws {
    let dir = try tempDir()
    let url = dir.appending(path: "accounts.json")

    #expect(throws: AccountLoadError.missing) {
        try AccountStore.load(from: url)
    }

    try json("{broken").write(to: url)
    #expect(throws: AccountLoadError.unreadable) {
        try AccountStore.load(from: url)
    }

    try json(#"{"schema":1,"revision":0,"prefs":{},"accounts":"not-an-array"}"#).write(to: url)
    #expect(throws: AccountLoadError.unreadable) {
        try AccountStore.load(from: url)
    }
}

@Test("validated load repairs a copy without rewriting raw bytes")
func validatedLoadRepairsWithoutWriting() throws {
    let dir = try tempDir()
    let url = dir.appending(path: "accounts.json")
    let original = json("""
    {"schema":1,"revision":4,
     "prefs":{"selectedAccountId":"acc_missing","rotateIntervalSec":900},
     "accounts":[
       {"id":"acc_valid","label":"  Claude  ","sourceKind":"claude-oauth","pinned":true,
        "credentials":{"configDir":"~/.claude"}}
     ]}
    """)
    try original.write(to: url)

    let raw = try AccountStore.load(from: url)
    let validated = try AccountStore.loadValidated(from: url, home: dir)

    #expect(raw.accounts[0].label == "  Claude  ")
    #expect(validated.accounts[0].label == "Claude")
    #expect(validated.prefs.selectedAccountId == "acc_valid")
    #expect(try Data(contentsOf: url) == original)
}

@Test("unknown source kind survives round trip")
func unknownSourceKindRoundTrip() throws {
    let kind = SourceKind(rawValue: "future-vendor-api")
    let registry = sampleRegistry(sourceKind: kind)
    let decoded = try AccountRegistry.decode(try AccountRegistry.encode(registry))
    #expect(decoded.accounts[0].sourceKind == kind)
    #expect(decoded.accounts[0].sourceKind.rawValue == "future-vendor-api")
}

@Test("keychain service and account survive round trip")
func keychainServiceAndAccountRoundTrip() throws {
    let registry = sampleRegistry()
    let keychain = registry.accounts[0].credentials.keychain
    #expect(keychain?.service == "Claude Code-credentials")
    #expect(keychain?.account == "user@example.com")

    let decoded = try AccountRegistry.decode(try AccountRegistry.encode(registry))
    #expect(decoded.accounts[0].credentials.keychain == keychain)
}
