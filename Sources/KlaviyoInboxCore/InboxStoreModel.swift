//
//  InboxStoreModel.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import CoreData

/// The Core Data model, built in code so there is no resource bundle to find from an extension and no
/// module-name lookup for a managed-object subclass: the entity class is plain `NSManagedObject`.
package enum InboxStoreModel {
    package static let entityName = "InboxMessage"

    package enum Key {
        package static let companyID = "companyID"
        package static let transmissionID = "transmissionID"
        package static let sortTime = "sortTime"
        package static let isRead = "isRead"
        package static let isArchived = "isArchived"
        /// When the message last changed (read or archive). Nil until it first does; a capture does not set it.
        package static let updatedAt = "updatedAt"
        /// When the message expires. Nil means it does not. A captured push has none, so only a message
        /// stored from the server will carry one.
        package static let expiresAt = "expiresAt"

        package static let payload = "payload"
    }

    package static let current: NSManagedObjectModel = makeCurrent()

    // To change the schema after release: edit `makeCurrent()`. The opener lets Core Data migrate an older
    // store with an inferred mapping, so the change must be one Core Data can infer (added optional
    // attributes, renames, and the like). Anything else needs a custom mapping model in the opener.

    private static func makeCurrent() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = entityName
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let attributes = [
            attribute(Key.companyID, .stringAttributeType),
            attribute(Key.transmissionID, .stringAttributeType),
            attribute(Key.sortTime, .dateAttributeType),
            attribute(Key.isRead, .booleanAttributeType, defaultValue: false),
            attribute(Key.isArchived, .booleanAttributeType, defaultValue: false),
            attribute(Key.updatedAt, .dateAttributeType, optional: true),
            attribute(Key.expiresAt, .dateAttributeType, optional: true),
            attribute(Key.payload, .binaryDataAttributeType)
        ]
        entity.properties = attributes
        entity.uniquenessConstraints = [[Key.transmissionID]]
        entity.indexes = [
            index("byCompanyAndSortTime", [Key.companyID, Key.sortTime, Key.transmissionID], in: attributes)
        ]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        if type == .binaryDataAttributeType {
            attribute.allowsExternalBinaryDataStorage = false
        }
        return attribute
    }

    private static func index(
        _ name: String,
        _ keys: [String],
        in attributes: [NSAttributeDescription]
    ) -> NSFetchIndexDescription {
        let elements = keys.compactMap { key in
            attributes.first { $0.name == key }.map {
                NSFetchIndexElementDescription(property: $0, collationType: .binary)
            }
        }
        return NSFetchIndexDescription(name: name, elements: elements)
    }
}
