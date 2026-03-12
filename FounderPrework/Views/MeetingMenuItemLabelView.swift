//
//  MeetingMenuItemLabelView.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 2/17/26.
//

import SwiftUI

struct MeetingMenuItemLabelView: View {
    let meeting: Meeting

    var body: some View {
        HStack {
            Text(meeting.title + " - " + meeting.timeRangeDescription)
                    .lineLimit(1)

            Spacer()

            memoStatusIcon
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var memoStatusIcon: some View {
        switch meeting.memoStatus {
        case .notStarted:
            EmptyView()
        case .inProgress:
            Image(systemName: "hourglass")
                .foregroundColor(.blue)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        }
    }
}
