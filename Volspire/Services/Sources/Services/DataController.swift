//
//  DataController.swift
//  Volspire
//
//

import CoreData

public final class DataController {
    public let container: NSPersistentContainer

    public init() {
        let modelURL = Bundle.module.url(forResource: "Volspire", withExtension: "momd")!
        let model = NSManagedObjectModel(contentsOf: modelURL)!
        container = NSPersistentContainer(name: "Volspire", managedObjectModel: model)

        container.loadPersistentStores { _, error in
            if let error {
                print("Core Data error: \(error)")
            }
        }
    }
}
