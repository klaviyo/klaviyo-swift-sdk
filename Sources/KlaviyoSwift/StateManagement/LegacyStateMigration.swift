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
/// Must run before `IdentityStore` is first hydrated, or the real identity gets clobbered by a
/// freshly-minted one.
///
/// The skip-check is shape-based (`apiKey != nil`), not path-based: mere presence of the legacy
/// file path can't mean "unmigrated" (older SDK versions used the same path for queue-only blobs).
///
/// Idempotent: every write is a full replace from the untouched source, so re-running after a
/// partial failure is always safe.
///
/// Retries immediately, in this same call; the shape-based (`apiKey != nil`) unmigrated marker
/// survives across launches until a migration succeeds, so a transient failure is safely retried
/// on the next cold launch.
func migrateLegacyStateIfNeeded(apiKey: String) {
    let legacyFile = klaviyoStateFile(apiKey: apiKey)
    guard let decoded = validatedLegacyState(apiKey: apiKey, legacyFile: legacyFile) else {
        return
    }

    let maxAttempts = 3
    for attempt in 1...maxAttempts {
        if attemptMigration(apiKey: apiKey, legacyFile: legacyFile, decoded: decoded) {
            return
        }
        if attempt < maxAttempts {
            environment.logger.error("LegacyStateMigration: retrying (\(attempt + 1)/\(maxAttempts)).")
        }
    }
}

/// One write-verify-retire attempt. `true` once the canonical stores hold `decoded` and the legacy
/// file has been retired so it can never be re-migrated.
private func attemptMigration(apiKey: String, legacyFile: URL, decoded: LegacyState) -> Bool {
    SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
    IdentityStore.shared.update(decoded.identity)
    IdentityStore.shared.updatePushToken(decoded.pushTokenData)

    do {
        try QueueStore.store(for: apiKey).restore(decoded.queue)
    } catch {
        environment.logger.error("LegacyStateMigration: failed to persist queue (\(error)).")
        return false
    }

    guard verifyMigration(apiKey: apiKey, decoded: decoded) else {
        environment.logger.error("LegacyStateMigration: verification failed.")
        return false
    }

    // Retire the legacy file so a future launch can NEVER re-migrate. This is load-bearing, not
    // cosmetic: `QueueStore` (not this file) is now the flush source, and it accumulates live
    // requests after init. A re-migration would call `restore` again and wholesale-replace that
    // live queue with the stale legacy snapshot — dropping everything enqueued since, and
    // re-sending the legacy backlog. Prefer deletion; if it fails, neutralize the file to an
    // apiKey-less shape that `validatedLegacyState` skips. Only a failure to BOTH leaves the
    // marker live, so retry the attempt in that case.
    do {
        try environment.fileClient.removeItem(legacyFile.path)
    } catch {
        do {
            // `{}` decodes as a `LegacyState` with `apiKey == nil`, which `validatedLegacyState`
            // treats as "already migrated" and skips.
            try environment.fileClient.write(Data("{}".utf8), legacyFile)
            environment.logger.error(
                "LegacyStateMigration: could not delete legacy file; neutralized its marker instead.")
        } catch {
            environment.logger.error(
                "LegacyStateMigration: could not delete or neutralize legacy file; will retry.")
            return false
        }
    }
    return true
}

/// Decodes and validates the legacy blob. Nil if absent, corrupt, already queue-only, claimed by
/// a different apiKey, or missing a recoverable anonymousId — in every case migration falls through
/// without touching any store, leaving the file in place for the next launch to retry.
private func validatedLegacyState(apiKey: String, legacyFile: URL) -> LegacyState? {
    guard environment.fileClient.fileExists(legacyFile.path) else { return nil }
    guard let legacyData = try? environment.dataFromUrl(legacyFile) else { return nil }
    guard let decoded: LegacyState = try? environment.decoder.decode(legacyData) else { return nil }
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
private func verifyMigration(apiKey: String, decoded: LegacyState) -> Bool {
    guard loadPersisted(PersistedConfig.self, fileName: StoreFile.config)?.apiKey == apiKey else {
        return false
    }
    guard let persistedIdentity = loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity),
          persistedIdentity.profile == decoded.identity,
          persistedIdentity.pushToken == decoded.pushTokenData else {
        return false
    }
    // A fresh instance forces a real disk read, decoupled from the registry singleton. `restore`
    // merge-prepends the legacy backlog, but a request that raced into the queue during the init
    // window can also front-insert (a `.high`-priority `enqueue` lands at index 0), so the legacy
    // backlog is not necessarily a positional prefix. Verify by id CONTAINMENT — every legacy id is
    // durably present — rather than by position; an exact/prefix check would spuriously fail on a
    // priority front-insert, leaving the legacy file un-retired and inviting a re-migration that
    // re-sends flushed ids and writes stale identity over post-init updates.
    let persistedIds = Set(QueueStore(apiKey: apiKey).requests.map(\.id))
    return Set(decoded.queue.map(\.id)).isSubset(of: persistedIds)
}
