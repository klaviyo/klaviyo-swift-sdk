//
//  KlaviyoUI.swift
//
//
//  Created by Ajay Subramanya on 9/12/24.
//

import Foundation

struct KlaviyoUIState {
    var companyId: String?
}

public struct KlaviyoUI {
    private static var state = KlaviyoUIState(companyId: nil)
    private static let fileName = "companyId.txt"

    
    public init() {
        if KlaviyoUI.state.companyId == nil {
            KlaviyoUI.state.companyId = KlaviyoUI.loadCompanyId()
        }
    }
    public func initilize(companyId: String) {
        KlaviyoUI.state.companyId = companyId
        KlaviyoUI.saveCompanyIdToFile(companyId)
    }
}


extension KlaviyoUI {
    
    // MARK: - Private File Persistence Methods

    private static func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func saveCompanyIdToFile(_ companyId: String) {
        let fileURL = getDocumentsDirectory().appendingPathComponent(fileName)
        do {
            try companyId.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Company ID saved to file.")
        } catch {
            print("Failed to save company ID: \(error)")
        }
    }

    private static func loadCompanyId() -> String? {
        let fileURL = getDocumentsDirectory().appendingPathComponent(fileName)
        do {
            let savedCompanyId = try String(contentsOf: fileURL, encoding: .utf8)
            print("Loaded Company ID from file.")
            return savedCompanyId
        } catch {
            print("No company ID found in file or failed to load: \(error)")
            return nil
        }
    }
}



