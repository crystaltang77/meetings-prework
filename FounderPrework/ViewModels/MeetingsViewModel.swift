//
//  MeetingsViewModel.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 2/17/26.
//

import Foundation
import Combine

@MainActor
final class MeetingsViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var selectedMeeting: Meeting?
    @Published var isLoadingCalendar = false
    @Published var calendarErrorMessage: String?
    @Published var now: Date = Date()  // drives "X minutes" updates

    private var timerCancellable: AnyCancellable?

    // TODO: Toggle this off when you’re done testing.
    private let useTestNow = false
    
    // Hardcoded test "now": Feb 20 2026 at 08:00 local time (example)
    private static let testNow: Date = {
        var comps = DateComponents()
                comps.year = 2026
                comps.month = 2
                comps.day = 27
                comps.hour = 9
                comps.minute = 1
                comps.second = 0
                return Calendar.current.date(from: comps)!
    }()
    
    init() {
        if useTestNow {
            now = Self.testNow
        } else {
            now = Date()
            startNowTimer()
        }
        Task {
            await loadMeetings()
        }
    }

    // MARK: - Menu bar title

    var menuBarTitle: String {
        guard let next = nextMeeting else {
            return "No more meetings today"
        }
        if let minutes = next.minutesUntilStart {
            return "Next: \(next.company) in \(minutes)m"
        } else {
            return "Now: \(next.company)"
        }
    }

    private var nextMeeting: Meeting? {
        meetings.first(where: { $0.startDate > now })
    }

    // MARK: - Timer

    private func startNowTimer() {
        timerCancellable = Timer
            .publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.now = Date()
            }
    }

    // MARK: - Calendar loading
    
    func loadMeetings() async {
            isLoadingCalendar = true
            calendarErrorMessage = nil
            do {
                try await CalendarManager.shared.requestAccessIfNeeded()
                
                let fetched = try CalendarManager.shared.fetchMeetings(for: now)

                self.meetings = fetched
            } catch CalendarError.accessDenied {
                calendarErrorMessage = "Calendar access denied. Enable it in System Settings → Privacy & Security → Calendars."
            } catch CalendarError.workCalendarNotFound {
                calendarErrorMessage = "Work calendar not found. Update `workCalendarTitle` in CalendarManager.swift to match your work calendar’s name."
            } catch {
                calendarErrorMessage = "Failed to load calendar events: \(error.localizedDescription)"
            }
            isLoadingCalendar = false
        }
    
    // MARK: - Memo handling

    func createMemo(for meeting: Meeting) {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { return }

        // Set status to inProgress immediately for UI feedback
        meetings[index].memoStatus = .inProgress
        selectedMeeting = meetings[index]

        Task {
            do {
                let memoText = try await GleanClient.shared.generateMemo(for: meeting)
                MemoStore.shared.setMemo(memoText, for: meeting.id)

                // Update local state
                if let updatedIndex = meetings.firstIndex(where: { $0.id == meeting.id }) {
                    meetings[updatedIndex].memo = memoText
                    meetings[updatedIndex].memoStatus = .ready
                    selectedMeeting = meetings[updatedIndex]
                }
            } catch {
                if let updatedIndex = meetings.firstIndex(where: { $0.id == meeting.id }) {
                    meetings[updatedIndex].memoStatus = .error("Failed to generate memo: \(error.localizedDescription)")
                    selectedMeeting = meetings[updatedIndex]
                }
            }
        }
    }
}
