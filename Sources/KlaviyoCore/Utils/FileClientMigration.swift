//
//  FileClientMigration.swift
//  KlaviyoSwift
//
//  Migration logic for moving SDK files from Library/ to Library/Application Support/com.klaviyo/
//

import Foundation

/// Returns the Application Support directory for Klaviyo files
/// - Returns: URL pointing to Library/Application Support/com.klaviyo/
public func klaviyoApplicationSupportDirectory() -> URL {
    let libraryDirectory = environment.fileClient.libraryDirectory()
    return libraryDirectory
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("com.klaviyo", isDirectory: true)
}

/// Migrates Klaviyo files from the old location (Library/) to the new location (Library/Application Support/com.klaviyo/)
/// This function is idempotent and safe to call multiple times.
///
/// - Parameter apiKey: The API key used to identify Klaviyo files
/// - Returns: The directory URL where files should be stored (new location if migration succeeded, old location if it failed)
public func migrateFilesIfNeeded(apiKey: String) -> URL {
    let newDirectory = klaviyoApplicationSupportDirectory()
    let oldDirectory = environment.fileClient.libraryDirectory()

    // Step 1: Create new directory if needed
    do {
        try environment.fileClient.createDirectory(newDirectory, true)
    } catch {
        environment.logger.error("Failed to create Application Support directory: \(error.localizedDescription)")
        return oldDirectory
    }

    // Step 2: Check if migration already completed
    let stateFileName = "klaviyo-\(apiKey)-state.json"
    let newStateFile = newDirectory.appendingPathComponent(stateFileName, isDirectory: false)

    if environment.fileClient.fileExists(newStateFile.path) {
        // Migration already completed
        return newDirectory
    }

    // Step 3: Check if old files exist
    let oldStateFile = oldDirectory.appendingPathComponent(stateFileName, isDirectory: false)

    if !environment.fileClient.fileExists(oldStateFile.path) {
        // Fresh install - no files to migrate
        return newDirectory
    }

    // Step 4: Perform migration
    let filesToMigrate = [
        "klaviyo-\(apiKey)-state.json",
        "klaviyo-\(apiKey)-events.plist",
        "klaviyo-\(apiKey)-people.plist"
    ]

    var migratedFiles: [String] = []

    for fileName in filesToMigrate {
        let oldFilePath = oldDirectory.appendingPathComponent(fileName, isDirectory: false).path
        let newFilePath = newDirectory.appendingPathComponent(fileName, isDirectory: false).path

        // Only migrate files that exist
        if environment.fileClient.fileExists(oldFilePath) {
            do {
                try environment.fileClient.copyItem(oldFilePath, newFilePath)
                migratedFiles.append(fileName)
            } catch {
                environment.logger.error("Failed to copy \(fileName): \(error.localizedDescription)")
                // Rollback: remove all migrated files
                rollbackMigration(directory: newDirectory, files: migratedFiles)
                return oldDirectory
            }
        }
    }

    // Step 5: Verify migration by checking if state file exists and has data
    if migratedFiles.contains(stateFileName) {
        guard environment.fileClient.fileExists(newStateFile.path),
              let stateData = try? environment.dataFromUrl(newStateFile),
              !stateData.isEmpty else {
            environment.logger.error("Failed to verify migrated state file")
            // Rollback: remove all migrated files
            rollbackMigration(directory: newDirectory, files: migratedFiles)
            return oldDirectory
        }
    }

    // Step 6: Cleanup old files
    for fileName in migratedFiles {
        let oldFilePath = oldDirectory.appendingPathComponent(fileName, isDirectory: false).path
        do {
            try environment.fileClient.removeItem(oldFilePath)
        } catch {
            environment.logger.error("Failed to remove old file \(fileName): \(error.localizedDescription)")
            // Continue anyway - migration succeeded, cleanup is best-effort
        }
    }

    environment.logger.error("Successfully migrated \(migratedFiles.count) file(s) to Application Support")
    return newDirectory
}

/// Removes all migrated files from the new directory in case of migration failure
/// - Parameters:
///   - directory: The directory containing the files to remove
///   - files: List of file names to remove
private func rollbackMigration(directory: URL, files: [String]) {
    for fileName in files {
        let filePath = directory.appendingPathComponent(fileName, isDirectory: false).path
        if environment.fileClient.fileExists(filePath) {
            do {
                try environment.fileClient.removeItem(filePath)
            } catch {
                environment.logger.error("Failed to rollback file \(fileName): \(error.localizedDescription)")
            }
        }
    }
}
