import Foundation

public enum AccountSelectionError: Error, Equatable {
    case accountNotFound(String)
    case accountNotPinned(String)
}

public enum AccountSelection {
    public static func pinnedAccounts(in registry: AccountRegistry) -> [Account] {
        registry.accounts.filter(\.pinned)
    }

    public static func select(
        id: String,
        now: Date,
        in registry: inout AccountRegistry
    ) throws {
        guard let account = registry.accounts.first(where: { $0.id == id }) else {
            throw AccountSelectionError.accountNotFound(id)
        }
        guard account.pinned else {
            throw AccountSelectionError.accountNotPinned(id)
        }
        registry.prefs.selectedAccountId = id
        registry.prefs.rotationAnchorAt = now.timeIntervalSince1970
    }

    public static func cycleSelected(now: Date, in registry: inout AccountRegistry) {
        let pinned = pinnedAccounts(in: registry)
        guard pinned.count > 1 else {
            let next = pinned.first?.id
            if registry.prefs.selectedAccountId != next {
                registry.prefs.selectedAccountId = next
                registry.prefs.rotationAnchorAt = now.timeIntervalSince1970
            }
            return
        }

        let nextIndex: Int
        if let selected = registry.prefs.selectedAccountId,
           let index = pinned.firstIndex(where: { $0.id == selected }) {
            nextIndex = (index + 1) % pinned.count
        } else {
            nextIndex = 0
        }
        registry.prefs.selectedAccountId = pinned[nextIndex].id
        registry.prefs.rotationAnchorAt = now.timeIntervalSince1970
    }

    public static func setPinned(
        id: String,
        pinned: Bool,
        now: Date,
        in registry: inout AccountRegistry
    ) throws {
        guard let index = registry.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountSelectionError.accountNotFound(id)
        }
        guard registry.accounts[index].pinned != pinned else { return }

        var resetAnchor = false
        if !pinned, registry.prefs.selectedAccountId == id {
            registry.prefs.selectedAccountId = nextPinnedID(after: index, excluding: id, in: registry)
            resetAnchor = true
        }
        registry.accounts[index].pinned = pinned

        let hasValidSelection = registry.prefs.selectedAccountId.flatMap { selectedID in
            registry.accounts.first(where: { $0.id == selectedID && $0.pinned })
        } != nil
        if !hasValidSelection {
            registry.prefs.selectedAccountId = pinnedAccounts(in: registry).first?.id
            resetAnchor = true
        }
        if resetAnchor {
            registry.prefs.rotationAnchorAt = now.timeIntervalSince1970
        }
    }

    public static func deleteAccount(
        id: String,
        now: Date,
        in registry: inout AccountRegistry
    ) throws {
        guard let index = registry.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountSelectionError.accountNotFound(id)
        }
        if registry.prefs.selectedAccountId == id {
            registry.prefs.selectedAccountId = nextPinnedID(after: index, excluding: id, in: registry)
            registry.prefs.rotationAnchorAt = now.timeIntervalSince1970
        }
        registry.accounts.remove(at: index)
    }

    public static func displayedAccount(at date: Date, in registry: AccountRegistry) -> Account? {
        let pinned = pinnedAccounts(in: registry)
        guard
            let selectedID = registry.prefs.selectedAccountId,
            let selectedIndex = pinned.firstIndex(where: { $0.id == selectedID })
        else { return nil }

        guard
            registry.prefs.rotateEnabled,
            pinned.count > 1,
            registry.prefs.rotateIntervalSec > 0,
            let anchor = registry.prefs.rotationAnchorAt
        else { return pinned[selectedIndex] }

        let elapsed = date.timeIntervalSince1970 - anchor
        guard elapsed.isFinite, elapsed >= 0 else { return pinned[selectedIndex] }

        let elapsedIntervals = floor(elapsed / Double(registry.prefs.rotateIntervalSec))
        guard elapsedIntervals.isFinite,
              elapsedIntervals < Double(Int.max) else {
            return pinned[selectedIndex]
        }
        let offset = Int(elapsedIntervals) % pinned.count
        return pinned[(selectedIndex + offset) % pinned.count]
    }

    // ponytail: circular registry scan; pinned-only ring if stable-order semantics change
    private static func nextPinnedID(
        after index: Int,
        excluding excludedID: String,
        in registry: AccountRegistry
    ) -> String? {
        guard registry.accounts.count > 1 else { return nil }
        for offset in 1..<registry.accounts.count {
            let account = registry.accounts[(index + offset) % registry.accounts.count]
            if account.id != excludedID, account.pinned { return account.id }
        }
        return nil
    }
}
