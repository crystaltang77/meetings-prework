//
//  MeetingSubmenuView.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 2/17/26.
//

import SwiftUI

struct MeetingSubmenuView: View {
    let meeting: Meeting
    let onCreateMemo: (Meeting) -> Void
    
    var body: some View {
        // Basic meeting info
        Text(meeting.title)
            .font(.headline)
            .foregroundColor(.primary)
        
        Divider()
        
        Group {
            switch meeting.memoStatus {
            case .notStarted:
                Button {
                    onCreateMemo(meeting)
                } label: {
                    Label("Create Pre-Meeting Memo", systemImage: "doc.text.magnifyingglass")
                }
                
                Text("Runs a Glean-powered research prompt for \(meeting.company).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
            case .inProgress:
                Text("Generating memo via Glean…")
                
            case .ready:
                if let memo = meeting.memo, !memo.isEmpty {
                    let lines = wrappedLines(from: memo)
                    
                    ForEach(lines.indices, id: \.self) { idx in
                        Text(lines[idx])
                            .font(.callout)
                            .foregroundColor(.primary)
                    }
                } else {
                    Text("Memo ready (no content cached).")
                        .foregroundColor(.red)
                }
                
            case .error(let message):
                Text("Failed to generate memo.")
                    .foregroundColor(.red)
                
                if !message.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        
        Group {
            switch meeting.memoStatus {
            case .notStarted:
                EmptyView()
            case .inProgress:
                EmptyView()
            case .ready:
                Button("Retry") {
                    onCreateMemo(meeting)
                }
                .font(.caption)
            case .error(let message):
                Button("Retry") {
                    onCreateMemo(meeting)
                }
                .font(.caption)
            }
        }
    }
    
    /// Break a long memo into multiple short lines by words so each line
    /// can be a separate menu row.
    private func wrappedLines(from memo: String,
                              maxLineLength: Int = 200,
                              maxLines: Int = 50) -> [String] {
        var result: [String] = []
        
        // 1) Split by newline into logical blocks
        let blocks = memo
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // 2) For each block, wrap by character length
        for block in blocks {
            var current = ""
            let words = block.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            
            for word in words {
                if current.isEmpty {
                    current = word
                } else if current.count + 1 + word.count <= maxLineLength {
                    current += " " + word
                } else {
                    result.append(current)
                    current = word
                    if result.count >= maxLines { return result }
                }
            }
            
            if !current.isEmpty {
                result.append(current)
                if result.count >= maxLines { return result }
            }
        }
        
        return result
    }
}
