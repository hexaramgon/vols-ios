//
//  PacksStore.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import Observation
import Services
import SharedUtilities

/// Single source of truth for the viewer's saved marketplace packs. The
/// Marketplace tab's "Saved packs" row, the Saved packs page and the pack
/// page's Save / Saved row all render from and mutate this one object, so a
/// save on the pack page is instantly reflected everywhere.
@MainActor @Observable
final class PacksStore {
    // MARK: Server state

    /// The viewer's saved packs (`get_saved_packs`), newest-saved first.
    private(set) var savedPacks: [ApiMarketplacePack] = []
    /// Defensive: flips on a confirmed response only (skeleton until then).
    private(set) var savedPacksLoaded = false
    /// The saved load failed with none on screen (offline) — Try again.
    private(set) var savedPacksFailed = false
    /// Lowercased ids of saved packs — the viewer truth for Save / Saved.
    private(set) var savedPackIds: Set<String> = []

    // MARK: Dependencies

    private let service: SupabaseService

    // MARK: In-flight guards

    private var savingIds: Set<String> = []
    private var savedTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(service: SupabaseService) {
        self.service = service

        // A pack was edited — saved rows show its new name / cover.
        observers.append(NotificationCenter.default.addObserver(
            forName: .packsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.savedPacksLoaded else { return }
                Task { await self.refreshSaved() }
            }
        })

        // Block/unblock changes which saved packs the server returns.
        observers.append(NotificationCenter.default.addObserver(
            forName: .userBlockStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.savedPacksLoaded else { return }
                Task { await self.refreshSaved() }
            }
        })
    }

    func resetForSignOut() {
        savedTask?.cancel()
        savedTask = nil
        savingIds = []
        savedPacks = []
        savedPacksLoaded = false
        savedPacksFailed = false
        savedPackIds = []
    }

    // MARK: - Loads

    func loadSavedIfNeeded() async {
        if let savedTask { return await savedTask.value }
        guard !savedPacksLoaded else { return }
        let task = Task { await fetchSaved() }
        savedTask = task
        await task.value
        savedTask = nil
    }

    func refreshSaved() async {
        await fetchSaved()
    }

    private func fetchSaved() async {
        do {
            // Free packs only while the paid marketplace is off.
            let rows = try await service.getSavedPacks()
                .filter { !FeatureFlags.freePacksOnly || ($0.price ?? 0) <= 0 }
            savedPacks = rows
            var ids = Set(rows.map { key($0.packId) })
            for id in savingIds { ids.insert(id) } // keep optimistic saves visible
            savedPackIds = ids
            savedPacksLoaded = true
            savedPacksFailed = false
        } catch {
            debugLog("[PacksStore] saved load: \(error)")
            savedPacksFailed = savedPacks.isEmpty
        }
    }

    // MARK: - Viewer save state

    func isSaved(_ packId: String) -> Bool {
        savedPackIds.contains(key(packId))
    }

    /// THE pack-save path. Optimistically flips the id-set and inserts/removes
    /// the row in the saved list, rolls back on failure. Returns the settled
    /// state, nil if nothing changed.
    @discardableResult
    func setSaved(_ save: Bool, pack: ApiMarketplacePack) async -> Bool? {
        let id = key(pack.packId)
        guard !savingIds.contains(id) else { return nil }
        savingIds.insert(id)
        // Saving's own subtle signature (tick-tick); a faint tap to unsave.
        if save { Haptics.save() } else { Haptics.unsave() }
        defer { savingIds.remove(id) }

        let removedIndex = savedPacks.firstIndex { key($0.packId) == id }
        let removedRow = removedIndex.map { savedPacks[$0] }
        if save {
            savedPackIds.insert(id)
            if removedIndex == nil { savedPacks.insert(pack, at: 0) }
        } else {
            savedPackIds.remove(id)
            if let removedIndex { savedPacks.remove(at: removedIndex) }
        }

        do {
            if save { try await service.savePack(packId: pack.packId) }
            else { try await service.unsavePack(packId: pack.packId) }
            return save
        } catch {
            if save {
                savedPackIds.remove(id)
                savedPacks.removeAll { key($0.packId) == id }
            } else {
                savedPackIds.insert(id)
                if let removedRow {
                    savedPacks.insert(removedRow, at: min(removedIndex ?? 0, savedPacks.count))
                }
            }
            debugLog("[PacksStore] setSaved failed: \(error)")
            return nil
        }
    }

    private func key(_ raw: String) -> String { raw.lowercased() }
}
