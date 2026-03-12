//
//  CalendarManager.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 2/17/26.
//

import Foundation
import EventKit

final class CalendarManager {
    static let shared = CalendarManager()

    private let eventStore = EKEventStore()

    private init() { }
    
    private func workCalendar() -> EKCalendar? {
        let targetTitle = GleanConfig.shared.workCalendarName
        // 1. Try cached identifier first
        let defaults = UserDefaults.standard
        let workCalendarIdentifierKey = "WorkCalendarIdentifier"
        if let id = defaults.string(forKey: workCalendarIdentifierKey),
           let calendar = eventStore.calendar(withIdentifier: id) {
            return calendar
        }

        // 2. Look up by title
        let all = eventStore.calendars(for: .event)
        if let calendar = all.first(where: { $0.title == targetTitle }) {
            defaults.set(calendar.calendarIdentifier, forKey: workCalendarIdentifierKey)
            return calendar
        }

        return nil
    }

    func requestAccessIfNeeded() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = try await eventStore.requestAccess(to: .event)
            if !granted {
                throw CalendarError.accessDenied
            }
        case .denied, .restricted, .fullAccess:
            // fullAccess is technically allowed, but keep as auth granted
            if status == .denied || status == .restricted {
                throw CalendarError.accessDenied
            }
        @unknown default:
            throw CalendarError.unknown
        }
    }
    
    func fetchMeetings(for referenceDate: Date = Date()) throws -> [Meeting] {
        let now = referenceDate
        let calendar = Calendar.current

        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        guard let workCal = workCalendar() else {
            throw CalendarError.workCalendarNotFound
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: [workCal]
        )
        let events = eventStore.events(matching: predicate)

        let remainingEvents = events
            .filter { $0.endDate > now }              // use the same reference "now"
            .sorted { $0.startDate < $1.startDate }

        return remainingEvents.map { event in
            let id = event.eventIdentifier ?? UUID().uuidString
            let title = event.title ?? "Untitled"

            let company: String
            if let firstWord = title.split(separator: " ").first {
                company = String(firstWord)
            } else {
                company = title
            }

            let storedMemo = MemoStore.shared.memo(for: id)

            return Meeting(
                id: id,
                title: title,
                company: company,
                startDate: event.startDate,
                endDate: event.endDate,
                memo: storedMemo,
                memoStatus: storedMemo == nil ? .notStarted : .ready
            )
        }
    }
}

// MARK: - Errors

enum CalendarError: Error {
    case accessDenied
    case workCalendarNotFound
    case unknown
}
