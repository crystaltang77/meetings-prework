//
//  MemoStore.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 2/17/26.
//

import Foundation

final class MemoStore {
    static let shared = MemoStore()

    private let userDefaultsKey = "MeetingMemos"

    // [meetingId: memoText]
    private var memos: [String: String] = [:]

    private init() {
        load()
    }

    func memo(for meetingId: String) -> String? {
        memos[meetingId]
    }

    func setMemo(_ memo: String, for meetingId: String) {
        memos[meetingId] = memo
        save()
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            memos = decoded
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(memos) {
            defaults.set(data, forKey: userDefaultsKey)
        }
    }
}
