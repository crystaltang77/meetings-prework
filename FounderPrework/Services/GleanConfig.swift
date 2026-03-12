//
//  GleanConfig.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 3/10/26.
//

import Foundation
import Combine

final class GleanConfig: ObservableObject {
    static let shared = GleanConfig()

    private let defaults = UserDefaults.standard
    private let instanceKey = "GleanInstance"
    private let tokenKey = "GleanApiToken"
    private let workCalendarNameKey = "WorkCalendarName"

    var instance: String {
        defaults.string(forKey: instanceKey) ?? "mongodb"
    }

    var apiToken: String? {
        defaults.string(forKey: tokenKey)
    }
    
    var workCalendarName: String {
        defaults.string(forKey: tokenKey) ?? "Work"
    }

    func save(instance: String, token: String, workCalendarName: String) {
        defaults.set(instance.trimmingCharacters(in: .whitespacesAndNewlines), forKey: instanceKey)
        defaults.set(token.trimmingCharacters(in: .whitespacesAndNewlines), forKey: tokenKey)
        defaults.set(workCalendarName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: workCalendarNameKey)
    }

    var isConfigured: Bool {
        if let t = apiToken { return !t.isEmpty }
        return false
    }
}
