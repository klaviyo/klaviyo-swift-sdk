//
//  MobileInboxPOC.swift
//
//  Throwaway storage experiment for MAGE-1002. This is intentionally not a
//  production Mobile Inbox API.
//

import CoreData
import Foundation

/// Configuration for the Mobile Inbox storage spike.
public struct MobileInboxPOCConfiguration: Equatable {
    public let appGroupIdentifier: String
    public let profileQuarantineWindow: TimeInterval
    /// Test-only fault injection for MAGE-1002. Never enable this in a product integration.
    public let forcePersistenceFailure: Bool
    /// Test-only fixture that makes Core Data open an intentionally malformed companion store.
    public let forceCorruptStore: Bool

    public init(
        appGroupIdentifier: String,
        profileQuarantineWindow: TimeInterval = 120,
        forcePersistenceFailure: Bool = false,
        forceCorruptStore: Bool = false
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.profileQuarantineWindow = profileQuarantineWindow
        self.forcePersistenceFailure = forcePersistenceFailure
        self.forceCorruptStore = forceCorruptStore
    }
}

/// The normalized subset of a Klaviyo push stored by the Mobile Inbox spike.
public struct MobileInboxPOCMessage: Equatable, Identifiable {
    public enum ProfileAssignment: Int16, Equatable {
        case assigned
        case quarantined
    }

    public let transmissionID: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let payloadTimestamp: Date?
    public let receivedAt: Date
    public let profileIdentifier: String?
    public let profileAssignment: ProfileAssignment

    public var id: String { transmissionID }
}

/// The capture outcome and the timings collected in the current process.
public struct MobileInboxPOCCaptureResult: Equatable {
    public enum Outcome: Equatable {
        case captured
        case duplicate
        case ignored
        case failed(String)
    }

    public let outcome: Outcome
    public let initializationMilliseconds: Double
    public let persistenceMilliseconds: Double
}

/// Records the current profile boundary used by the timestamp/quarantine experiment.
public struct MobileInboxPOCProfileTransition: Equatable {
    public let fromProfileIdentifier: String?
    public let toProfileIdentifier: String?
    public let occurredAt: Date

    public init(fromProfileIdentifier: String?, toProfileIdentifier: String?, occurredAt: Date = Date()) {
        self.fromProfileIdentifier = fromProfileIdentifier
        self.toProfileIdentifier = toProfileIdentifier
        self.occurredAt = occurredAt
    }
}

/// Owns a Darwin notification observer. Keep a strong reference for as long as updates are needed.
public final class MobileInboxPOCChangeObserver {
    private let notificationName: CFNotificationName
    private let callback: () -> Void

    fileprivate init(notificationName: String, callback: @escaping () -> Void) {
        self.notificationName = CFNotificationName(notificationName as CFString)
        self.callback = callback
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            mobileInboxPOCDarwinNotificationCallback,
            self.notificationName.rawValue,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            notificationName,
            nil
        )
    }

    fileprivate func notify() {
        DispatchQueue.main.async(execute: callback)
    }
}

private func mobileInboxPOCDarwinNotificationCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    Unmanaged<MobileInboxPOCChangeObserver>.fromOpaque(observer).takeUnretainedValue().notify()
}

/// A throwaway Core Data proof of concept for an NSE and host app sharing an inbox.
///
/// `capture` catches every persistence error so an NSE caller can always continue with normal
/// notification delivery. It deliberately does no rich-media work.
public enum MobileInboxPOC {
    private static let storeFilename = "klaviyo-mobile-inbox-poc.sqlite"
    private static let corruptStoreFilename = "klaviyo-mobile-inbox-poc-corrupt.sqlite"
    private static let notificationPrefix = "com.klaviyo.mobile-inbox-poc.changed."
    /// Shared App Group flag consumed by the NSE to test capture failure handling once.
    public static let forceNextCaptureFailureUserDefaultsKey = "mobileInboxPOCForceNextCaptureFailure"
    /// Shared App Group flag consumed by the NSE to test a real malformed SQLite store once.
    public static let forceNextCorruptStoreUserDefaultsKey = "mobileInboxPOCForceNextCorruptStore"

    /// Captures a Klaviyo push before rich media or notification presentation work begins.
    /// A missing `tm` is ignored because it cannot be safely deduplicated.
    public static func capture(
        userInfo: [AnyHashable: Any],
        title: String,
        subtitle: String,
        body: String,
        configuration: MobileInboxPOCConfiguration,
        currentProfileIdentifier: String? = nil,
        receivedAt: Date = Date()
    ) -> MobileInboxPOCCaptureResult {
        guard let transmissionID = transmissionID(from: userInfo), !transmissionID.isEmpty else {
            return MobileInboxPOCCaptureResult(outcome: .ignored, initializationMilliseconds: 0, persistenceMilliseconds: 0)
        }

        let initializationStart = ProcessInfo.processInfo.systemUptime
        do {
            if configuration.forceCorruptStore {
                try writeCorruptStore(for: configuration)
            }
            let store = try MobileInboxPOCStore(configuration: configuration)
            let initializationMilliseconds = milliseconds(since: initializationStart)
            let persistenceStart = ProcessInfo.processInfo.systemUptime
            let result = try store.insert(
                transmissionID: transmissionID,
                title: title,
                subtitle: subtitle,
                body: body,
                payloadTimestamp: payloadTimestamp(from: userInfo),
                currentProfileIdentifier: currentProfileIdentifier,
                receivedAt: receivedAt
            )
            let persistenceMilliseconds = milliseconds(since: persistenceStart)
            if result == .captured {
                postChangeNotification(for: configuration)
            }
            return MobileInboxPOCCaptureResult(
                outcome: result,
                initializationMilliseconds: initializationMilliseconds,
                persistenceMilliseconds: persistenceMilliseconds
            )
        } catch {
            return MobileInboxPOCCaptureResult(
                outcome: .failed(error.localizedDescription),
                initializationMilliseconds: milliseconds(since: initializationStart),
                persistenceMilliseconds: 0
            )
        }
    }

    public static func messages(configuration: MobileInboxPOCConfiguration) throws -> [MobileInboxPOCMessage] {
        try MobileInboxPOCStore(configuration: configuration).messages()
    }

    public static func recordProfileTransition(
        _ transition: MobileInboxPOCProfileTransition,
        configuration: MobileInboxPOCConfiguration
    ) throws {
        try MobileInboxPOCStore(configuration: configuration).record(transition: transition)
        postChangeNotification(for: configuration)
    }

    public static func observeChanges(
        configuration: MobileInboxPOCConfiguration,
        using callback: @escaping () -> Void
    ) -> MobileInboxPOCChangeObserver {
        MobileInboxPOCChangeObserver(notificationName: notificationName(for: configuration), callback: callback)
    }

    /// Klaviyo's delivery-specific identifier is nested in `body._k.tm`.
    /// This mirrors the SDK's push-open deduplication contract.
    static func transmissionID(from userInfo: [AnyHashable: Any]) -> String? {
        stringValue(from: klaviyoMetadataValue(named: "tm", in: userInfo))
    }

    static func payloadTimestamp(from userInfo: [AnyHashable: Any]) -> Date? {
        let value = klaviyoMetadataValue(named: "t", in: userInfo)
        if let seconds = value as? NSNumber {
            return Date(timeIntervalSince1970: seconds.doubleValue)
        }
        if let seconds = value as? Double {
            return Date(timeIntervalSince1970: seconds)
        }
        if let string = value as? String {
            if let seconds = TimeInterval(string) {
                return Date(timeIntervalSince1970: seconds)
            }
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }

    /// APNs may bridge nested JSON dictionaries either as `[String: Any]`,
    /// `[AnyHashable: Any]`, or `NSDictionary`; handle all three forms.
    private static func klaviyoMetadataValue(named key: String, in userInfo: [AnyHashable: Any]) -> Any? {
        dictionaryValue(for: "_k", in: dictionaryValue(for: "body", in: userInfo))?[key]
    }

    private static func dictionaryValue(for key: String, in values: [AnyHashable: Any]) -> [String: Any]? {
        dictionaryValue(from: values[key])
    }

    private static func dictionaryValue(for key: String, in values: [String: Any]?) -> [String: Any]? {
        guard let values else { return nil }
        return dictionaryValue(from: values[key])
    }

    private static func dictionaryValue(from value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let dictionary = value as? [AnyHashable: Any] {
            return Dictionary(uniqueKeysWithValues: dictionary.compactMap { key, value in
                (key as? String).map { ($0, value) }
            })
        }
        if let dictionary = value as? NSDictionary {
            return Dictionary(uniqueKeysWithValues: dictionary.compactMap { key, value in
                (key as? String).map { ($0, value) }
            })
        }
        return nil
    }

    private static func stringValue(from value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func postChangeNotification(for configuration: MobileInboxPOCConfiguration) {
        let name = CFNotificationName(notificationName(for: configuration) as CFString)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, nil, nil, true)
    }

    private static func notificationName(for configuration: MobileInboxPOCConfiguration) -> String {
        notificationPrefix + configuration.appGroupIdentifier
    }

    private static func milliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1000
    }

    fileprivate static func storeURL(for configuration: MobileInboxPOCConfiguration) throws -> URL {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: configuration.appGroupIdentifier
        ) else {
            throw MobileInboxPOCError.appGroupUnavailable(configuration.appGroupIdentifier)
        }
        let filename = configuration.forceCorruptStore ? corruptStoreFilename : storeFilename
        return directory.appendingPathComponent(filename)
    }

    private static func writeCorruptStore(for configuration: MobileInboxPOCConfiguration) throws {
        let data = Data("MAGE-1002 intentionally malformed SQLite test file".utf8)
        try data.write(to: storeURL(for: configuration), options: .atomic)
    }
}

private enum MobileInboxPOCError: LocalizedError {
    case appGroupUnavailable(String)
    case forcedPersistenceFailure

    var errorDescription: String? {
        switch self {
        case let .appGroupUnavailable(identifier):
            return "The App Group '\(identifier)' is unavailable."
        case .forcedPersistenceFailure:
            return "Test-only forced Mobile Inbox persistence failure."
        }
    }
}

private final class MobileInboxPOCStore {
    private let configuration: MobileInboxPOCConfiguration
    private let context: NSManagedObjectContext
    private let messageEntity: NSEntityDescription
    private let transitionEntity: NSEntityDescription

    init(configuration: MobileInboxPOCConfiguration) throws {
        self.configuration = configuration
        let model = Self.makeModel()
        guard let messageEntity = model.entitiesByName["InboxMessage"],
              let transitionEntity = model.entitiesByName["ProfileTransition"] else {
            fatalError("Mobile Inbox POC model is malformed")
        }
        self.messageEntity = messageEntity
        self.transitionEntity = transitionEntity

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let options: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
            NSSQLitePragmasOption: ["journal_mode": "WAL"]
        ]
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: MobileInboxPOC.storeURL(for: configuration),
            options: options
        )

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        self.context = context
    }

    func insert(
        transmissionID: String,
        title: String,
        subtitle: String,
        body: String,
        payloadTimestamp: Date?,
        currentProfileIdentifier: String?,
        receivedAt: Date
    ) throws -> MobileInboxPOCCaptureResult.Outcome {
        try performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "InboxMessage")
            request.predicate = NSPredicate(format: "transmissionID == %@", transmissionID)
            request.fetchLimit = 1
            if try context.count(for: request) > 0 {
                return .duplicate
            }

            let profile = try profileAssignment(
                for: payloadTimestamp,
                currentProfileIdentifier: currentProfileIdentifier
            )
            let message = NSManagedObject(entity: messageEntity, insertInto: context)
            message.setValue(transmissionID, forKey: "transmissionID")
            message.setValue(title, forKey: "title")
            message.setValue(subtitle, forKey: "subtitle")
            message.setValue(body, forKey: "body")
            message.setValue(payloadTimestamp, forKey: "payloadTimestamp")
            message.setValue(receivedAt, forKey: "receivedAt")
            message.setValue(profile.assignment.rawValue, forKey: "profileAssignment")
            message.setValue(profile.identifier, forKey: "profileIdentifier")

            do {
                if configuration.forcePersistenceFailure {
                    context.rollback()
                    throw MobileInboxPOCError.forcedPersistenceFailure
                }
                try context.save()
                return .captured
            } catch {
                context.rollback()
                if try context.count(for: request) > 0 {
                    return .duplicate
                }
                throw error
            }
        }
    }

    func messages() throws -> [MobileInboxPOCMessage] {
        try performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "InboxMessage")
            request.sortDescriptors = [NSSortDescriptor(key: "receivedAt", ascending: false)]
            return try context.fetch(request).compactMap { object in
                guard let transmissionID = object.value(forKey: "transmissionID") as? String,
                      let title = object.value(forKey: "title") as? String,
                      let subtitle = object.value(forKey: "subtitle") as? String,
                      let body = object.value(forKey: "body") as? String,
                      let receivedAt = object.value(forKey: "receivedAt") as? Date,
                      let rawAssignment = object.value(forKey: "profileAssignment") as? Int16,
                      let assignment = MobileInboxPOCMessage.ProfileAssignment(rawValue: rawAssignment) else {
                    return nil
                }
                return MobileInboxPOCMessage(
                    transmissionID: transmissionID,
                    title: title,
                    subtitle: subtitle,
                    body: body,
                    payloadTimestamp: object.value(forKey: "payloadTimestamp") as? Date,
                    receivedAt: receivedAt,
                    profileIdentifier: object.value(forKey: "profileIdentifier") as? String,
                    profileAssignment: assignment
                )
            }
        }
    }

    func record(transition: MobileInboxPOCProfileTransition) throws {
        try performAndWait {
            let object = NSManagedObject(entity: transitionEntity, insertInto: context)
            object.setValue(UUID().uuidString, forKey: "identifier")
            object.setValue(transition.fromProfileIdentifier, forKey: "fromProfileIdentifier")
            object.setValue(transition.toProfileIdentifier, forKey: "toProfileIdentifier")
            object.setValue(transition.occurredAt, forKey: "occurredAt")
            try context.save()
        }
    }

    private func profileAssignment(
        for payloadTimestamp: Date?,
        currentProfileIdentifier: String?
    ) throws -> (assignment: MobileInboxPOCMessage.ProfileAssignment, identifier: String?) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ProfileTransition")
        request.sortDescriptors = [NSSortDescriptor(key: "occurredAt", ascending: false)]
        request.fetchLimit = 1
        guard let transition = try context.fetch(request).first,
              let occurredAt = transition.value(forKey: "occurredAt") as? Date else {
            return (.assigned, currentProfileIdentifier)
        }
        let identifier = currentProfileIdentifier ?? transition.value(forKey: "toProfileIdentifier") as? String
        guard let payloadTimestamp else { return (.assigned, identifier) }
        if abs(payloadTimestamp.timeIntervalSince(occurredAt)) <= configuration.profileQuarantineWindow {
            return (.quarantined, nil)
        }
        return (.assigned, identifier)
    }

    /// `NSManagedObjectContext` only gained a throwing, value-returning overload in iOS 15.
    /// The SDK supports iOS 13, so bridge the older callback API here for the spike.
    private func performAndWait<Value>(_ work: () throws -> Value) throws -> Value {
        var result: Result<Value, Error>!
        context.performAndWait {
            result = Result(catching: work)
        }
        return try result.get()
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        // MAGE-1002 migration probe: v3 adds an optional attribute so a v2 store must use
        // Core Data's inferred lightweight migration path when opened by the NSE.
        model.versionIdentifiers = ["MAGE-1002-v3"]

        let message = NSEntityDescription()
        message.name = "InboxMessage"
        message.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        message.properties = [
            attribute("transmissionID", type: .stringAttributeType),
            attribute("title", type: .stringAttributeType),
            attribute("subtitle", type: .stringAttributeType),
            attribute("body", type: .stringAttributeType),
            attribute("payloadTimestamp", type: .dateAttributeType, optional: true),
            attribute("receivedAt", type: .dateAttributeType),
            attribute("profileIdentifier", type: .stringAttributeType, optional: true),
            attribute("profileAssignment", type: .integer16AttributeType),
            attribute("migrationProbe", type: .stringAttributeType, optional: true)
        ]
        message.uniquenessConstraints = [["transmissionID"]]

        let transition = NSEntityDescription()
        transition.name = "ProfileTransition"
        transition.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        transition.properties = [
            attribute("identifier", type: .stringAttributeType),
            attribute("fromProfileIdentifier", type: .stringAttributeType, optional: true),
            attribute("toProfileIdentifier", type: .stringAttributeType, optional: true),
            attribute("occurredAt", type: .dateAttributeType)
        ]
        transition.uniquenessConstraints = [["identifier"]]

        model.entities = [message, transition]
        return model
    }

    private static func attribute(
        _ name: String,
        type: NSAttributeType,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}
