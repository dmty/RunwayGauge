import Dispatch
import Foundation
import Testing
@testable import UsageCore

@Suite("AccountConcurrencyTests")
struct AccountConcurrencyTests {
    private func tempURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "account-concurrency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "accounts.json")
    }

    private func account(id: String) -> Account {
        Account(
            id: id,
            label: id,
            sourceKind: .claudeOAuth,
            pinned: true,
            credentials: AccountCredentials()
        )
    }

    private func emptyRegistry(revision: UInt64 = 0) -> AccountRegistry {
        AccountRegistry(
            revision: revision,
            prefs: AccountPreferences(),
            accounts: []
        )
    }

    @Test("two concurrent mutations both survive and advance revision twice")
    func concurrentMutationsSurvive() throws {
        let url = try tempURL()
        try AccountStore.save(emptyRegistry(revision: 40), to: url)

        DispatchQueue.concurrentPerform(iterations: 2) { index in
            _ = try? AccountStore.mutate(at: url) { registry in
                registry.accounts.append(account(id: "acc_\(index)"))
            }
        }

        let loaded = try AccountStore.load(from: url)
        #expect(Set(loaded.accounts.map(\.id)) == ["acc_0", "acc_1"])
        #expect(loaded.revision == 42)
    }

    @Test("throwing mutation leaves original bytes unchanged")
    func throwingMutationPreservesBytes() throws {
        enum Expected: Error { case stop }

        let url = try tempURL()
        try AccountStore.save(emptyRegistry(revision: 8), to: url)
        let before = try Data(contentsOf: url)

        #expect(throws: Expected.stop) {
            try AccountStore.mutate(at: url) { registry in
                registry.accounts.append(account(id: "acc_never_saved"))
                throw Expected.stop
            }
        }

        #expect(try Data(contentsOf: url) == before)
        #expect(try AccountStore.load(from: url) == emptyRegistry(revision: 8))
    }

    @Test("mutation atomically replaces an existing destination")
    func replacesExistingDestination() throws {
        let url = try tempURL()
        try AccountStore.save(emptyRegistry(revision: 3), to: url)

        let result = try AccountStore.mutate(at: url) {
            $0.accounts.append(account(id: "acc_new"))
        }

        #expect(result.revision == 4)
        #expect(try AccountStore.load(from: url) == result)
    }

    @Test("commit revision ignores a revision assigned by the mutation body")
    func derivesRevisionFromLockedSnapshot() throws {
        let url = try tempURL()
        try AccountStore.save(emptyRegistry(revision: 41), to: url)

        let result = try AccountStore.mutate(at: url) {
            $0.revision = 0
            $0.accounts.append(account(id: "acc_new"))
        }

        #expect(result.revision == 42)
        #expect(try AccountStore.load(from: url).revision == 42)
    }

    @Test("mutation cannot persist an unsupported schema")
    func rejectsSchemaChangeBeforeCommit() throws {
        let url = try tempURL()
        try AccountStore.save(emptyRegistry(revision: 12), to: url)
        let before = try Data(contentsOf: url)

        #expect(throws: AccountValidationError.unsupportedSchema(2)) {
            try AccountStore.mutate(at: url) {
                $0.schema = 2
            }
        }

        #expect(try Data(contentsOf: url) == before)
    }

    @Test("mutation creates a missing destination under the same lock")
    func createsMissingDestination() throws {
        let url = try tempURL()

        let result = try AccountStore.mutate(at: url) {
            $0.accounts.append(account(id: "acc_first"))
        }

        #expect(result.revision == 1)
        #expect(try AccountStore.load(from: url) == result)
    }

    @Test("revision overflow is rejected without changing bytes")
    func rejectsRevisionOverflow() throws {
        let url = try tempURL()
        try AccountStore.save(emptyRegistry(revision: .max), to: url)
        let before = try Data(contentsOf: url)

        #expect(throws: AccountStoreError.revisionOverflow) {
            try AccountStore.mutate(at: url) { $0.revision = 0 }
        }
        #expect(try Data(contentsOf: url) == before)
    }
}
