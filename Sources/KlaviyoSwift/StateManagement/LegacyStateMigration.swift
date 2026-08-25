//
//  LegacyStateMigration.swift
//  klaviyo-swift-sdk
//
//  One-time migration: legacy klaviyo-{apiKey}-state.json -> the three canonical
//  KlaviyoCore stores (SDKConfigStore / IdentityStore / QueueStore).
//

import Foundation
import KlaviyoCore

/// Lifts a pre-split legacy state file into the canonical Core stores, then retires it.
///
/// Must run before `loadKlaviyoStateFromDisk` and before `IdentityStore` is first hydrated, or
/// the real identity gets clobbered by a freshly-minted one.
///
/// The skip-check is shape-based (`apiKey != nil`), not path-based: this same file path stays in
/// use for ongoing queue-only persistence until MAGE-952, so mere presence can't mean "unmigrated."
///
/// Idempotent: every write is a full replace from the untouched source, so re-running after a
/// partial failure is always safe.
func migrateLegacyStateIfNeeded(apiKey: String) {
    let legacyFile = klaviyoStateFile(apiKey: apiKey)
    guard let decoded = validatedLegacyState(apiKey: apiKey, legacyFile: legacyFile) else {
        return
    }

    SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
    IdentityStore.shared.update(decoded.identity)
    IdentityStore.shared.updatePushToken(decoded.pushTokenData)

    do {
        try QueueStore.store(for: apiKey).restore(decoded.queue)
    } catch {
        environment.logger.error("LegacyStateMigration: failed to persist queue (\(error)); will retry.")
        return
    }

    guard verifyMigration(apiKey: apiKey, decoded: decoded) else {
        environment.logger.error("LegacyStateMigration: verification failed; will retry.")
        return
    }

    do {
        try environment.fileClient.removeItem(legacyFile.path)
    } catch {
        environment.logger.error("LegacyStateMigration: migrated but failed to remove legacy file.")
    }
}

/// Decodes and validates the legacy blob. Nil if absent, corrupt, already queue-only, claimed by
/// a different apiKey, or missing a recoverable anonymousId — in every case, unchanged callers
/// (`loadKlaviyoStateFromDisk`, etc.) are left to handle the file as they already do today.
private func validatedLegacyState(apiKey: String, legacyFile: URL) -> KlaviyoState? {
    guard environment.fileClient.fileExists(legacyFile.path) else { return nil }
    guard let legacyData = try? environment.dataFromUrl(legacyFile) else { return nil }
    guard let decoded: KlaviyoState = try? environment.decoder.decode(legacyData) else { return nil }
    guard let decodedApiKey = decoded.apiKey else { return nil }
    guard decodedApiKey == apiKey else {
        environment.logger.error("LegacyStateMigration: legacy file for \(apiKey) claims a different apiKey.")
        return nil
    }
    guard decoded.identity.anonymousId != nil else {
        // Every real legacy blob has one, minted before the SDK ever wrote a state file.
        environment.logger.error("LegacyStateMigration: legacy file for \(apiKey) has no anonymousId.")
        return nil
    }
    return decoded
}

/// Verifies all three stores from disk (not the singletons' cached values) before deletion, so a
/// swallowed write failure can't slip through.
private func verifyMigration(apiKey: String, decoded: KlaviyoState) -> Bool {
    guard loadPersisted(PersistedConfig.self, fileName: StoreFile.config)?.apiKey == apiKey else {
        return false
    }
    guard let persistedIdentity = loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity),
          persistedIdentity.profile == decoded.identity,
          persistedIdentity.pushToken == decoded.pushTokenData else {
        return false
    }
    // A fresh instance forces a real disk read, decoupled from the registry singleton.
    return QueueStore(apiKey: apiKey).requests == decoded.queue
}
