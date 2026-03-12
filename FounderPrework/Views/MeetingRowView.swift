//
//  MeetingRowView.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 2/17/26.
//

import SwiftUI

struct MeetingRowView: View {
    let meeting: Meeting
    let isPinned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(meeting.title)
                .font(.subheadline)
                .lineLimit(1)
                .fontWeight(isPinned ? .semibold : .regular)

            Text(meeting.timeRangeDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            if let minutes = meeting.minutesUntilStart {
                Text("Starts in \(minutes)m")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if meeting.startDate <= Date() {
                Text("In progress")
                    .font(.caption2)
                    .foregroundColor(.green)
            }

            memoStatusLabel
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isPinned ? Color.accentColor.opacity(0.15) : Color.clear)
                )
    }

    @ViewBuilder
    private var memoStatusLabel: some View {
        switch meeting.memoStatus {
        case .notStarted:
            EmptyView()
        case .inProgress:
            Text("Memo: generating…")
                .font(.caption2)
                .foregroundColor(.blue)
        case .ready:
            Text("Memo: ready")
                .font(.caption2)
                .foregroundColor(.green)
        case .error:
            Text("Memo: error")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }
}
