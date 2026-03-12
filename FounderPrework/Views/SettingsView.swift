//
//  SettingsView.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 3/10/26.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var config = GleanConfig.shared
    
    @State private var instance = GleanConfig.shared.instance
    @State private var token = GleanConfig.shared.apiToken ?? ""
    @State private var workCalendarName = GleanConfig.shared.workCalendarName
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading) {
            Grid(alignment: .leading) {
                GridRow {
                    Text("Instance")
                    TextField("e.g. mongodb", text: $instance)
                        .textFieldStyle(.roundedBorder)
                        .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text("Glean API Key")
                    SecureField("API Key", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text("Calendar Name")
                    TextField("e.g. crystal.tang@mongodb.com", text: $workCalendarName)
                        .textFieldStyle(.roundedBorder)
                        .gridColumnAlignment(.leading)
                }
            }

            HStack {
                if saved {
                    Text("Saved").foregroundColor(.green).font(.caption)
                }
                Spacer()
                Button("Save") {
                    GleanConfig.shared.save(instance: instance, token: token, workCalendarName: workCalendarName)
                    saved = true
                }
            }
        }
        .padding(16)
    }
}

