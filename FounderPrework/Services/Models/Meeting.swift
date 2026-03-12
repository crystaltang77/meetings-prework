//
//  Meeting.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 2/17/26.
//

import Foundation

enum MemoStatus: Equatable {
    case notStarted
    case inProgress
    case ready
    case error(String)
}

struct Meeting: Identifiable, Equatable {
    let id: String              // Backed by EKEvent.eventIdentifier or synthetic
    let title: String
    let company: String
    let startDate: Date
    let endDate: Date?
    var memo: String?
    var memoStatus: MemoStatus

    var isInFuture: Bool {
        startDate > Date()
    }

    var minutesUntilStart: Int? {
        let interval = startDate.timeIntervalSinceNow
        guard interval > 0 else { return nil }
        return Int(interval / 60.0)
    }

    var timeRangeDescription: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        if let end = endDate {
            return "\(formatter.string(from: startDate)) – \(formatter.string(from: end))"
        } else {
            return formatter.string(from: startDate)
        }
    }
}
