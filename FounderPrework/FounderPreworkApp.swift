//
//  FounderPreworkApp.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 2/17/26.
//

import SwiftUI

@main
struct FounderPreworkApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel = MeetingsViewModel()
    
    var body: some Scene {
            MenuBarExtra {
                Text("Today’s Meetings")
                    .font(.headline)

                if viewModel.isLoadingCalendar {
                    Text("Loading…")
                } else if let error = viewModel.calendarErrorMessage {
                    Text(error)
                        .foregroundColor(.red)
                } else if viewModel.meetings.isEmpty {
                    Text("No more meetings today")
                } else {
                    ForEach(viewModel.meetings) { meeting in
                        Menu {
                            MeetingSubmenuView(
                                meeting: meeting,
                                onCreateMemo: { m in
                                    viewModel.createMemo(for: m)
                                }
                            )
                        } label: {
                            MeetingMenuItemLabelView(meeting: meeting)
                        }
                    }
                }
                
                Divider()
                
                Button {
                    Task { await viewModel.loadMeetings() }
                } label: {
                    if viewModel.isLoadingCalendar {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Refresh")
                            .help("Refresh")
                    }
                }
                
                Divider()
                
                Button("Settings…") {
                    openWindow(id: "settings")
                }
                
            } label: {
                Text(viewModel.menuBarTitle)
            }
        
        Window("Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 380, height: 200)
    }
}
