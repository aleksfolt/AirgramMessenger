import Foundation
import Postbox
import SwiftSignalKit

public enum AirgramSettings {
    private static let prefix = "airgram_"
    private static let hiddenAuthorsKey = "airgram_hiddenAuthors"

    private static let version = Atomic<Int>(value: 0)
    private static let versionPromise = ValuePromise<Int>(0, ignoreRepeated: false)

    public static var changes: Signal<Int, NoError> {
        return self.versionPromise.get()
    }

    private static func notify() {
        let value = self.version.modify { $0 + 1 }
        self.versionPromise.set(value)
    }

    private static func bool(_ name: String, defaultValue: Bool) -> Bool {
        return UserDefaults.standard.object(forKey: self.prefix + name) as? Bool ?? defaultValue
    }

    private static func set(_ value: Bool, for name: String) {
        UserDefaults.standard.set(value, forKey: self.prefix + name)
        self.notify()
    }

    public static var hidePhoneInSettings: Bool {
        get {
            return self.bool("hidePhoneInSettings", defaultValue: false)
        }
        set {
            self.set(newValue, for: "hidePhoneInSettings")
        }
    }

    public static var secondsInMessages: Bool {
        get {
            return self.bool("secondsInMessages", defaultValue: false)
        }
        set {
            self.set(newValue, for: "secondsInMessages")
        }
    }

    public static var confirmCalls: Bool {
        get {
            return self.bool("confirmCalls", defaultValue: false)
        }
        set {
            self.set(newValue, for: "confirmCalls")
        }
    }

    public static var keepViewOnceMedia: Bool {
        get {
            return self.bool("keepViewOnceMedia", defaultValue: true)
        }
        set {
            self.set(newValue, for: "keepViewOnceMedia")
        }
    }

    private static func storedHiddenAuthors() -> [String: [String]] {
        return UserDefaults.standard.dictionary(forKey: self.hiddenAuthorsKey) as? [String: [String]] ?? [:]
    }

    public static var hiddenAuthors: [Int64: [Int64]] {
        var result: [Int64: [Int64]] = [:]
        for (key, value) in self.storedHiddenAuthors() {
            if let peerId = Int64(key) {
                let authors = value.compactMap { Int64($0) }
                if !authors.isEmpty {
                    result[peerId] = authors
                }
            }
        }
        return result
    }

    public static func hiddenAuthorIds(peerId: PeerId) -> Set<Int64> {
        guard let stored = self.storedHiddenAuthors()[String(peerId.toInt64())] else {
            return Set()
        }
        return Set(stored.compactMap { Int64($0) })
    }

    public static func isAuthorHidden(peerId: PeerId, authorId: PeerId) -> Bool {
        return self.hiddenAuthorIds(peerId: peerId).contains(authorId.toInt64())
    }

    public static func setAuthorHidden(_ hidden: Bool, peerId: PeerId, authorId: PeerId) {
        var all = self.storedHiddenAuthors()
        let key = String(peerId.toInt64())
        var authors = all[key] ?? []
        let author = String(authorId.toInt64())
        if hidden {
            if !authors.contains(author) {
                authors.append(author)
            }
        } else {
            authors.removeAll(where: { $0 == author })
        }
        if authors.isEmpty {
            all.removeValue(forKey: key)
        } else {
            all[key] = authors
        }
        UserDefaults.standard.set(all, forKey: self.hiddenAuthorsKey)
        self.notify()
    }

    public static func hiddenAuthorsSignal(peerId: PeerId) -> Signal<Set<Int64>, NoError> {
        return self.changes
        |> map { _ in
            return AirgramSettings.hiddenAuthorIds(peerId: peerId)
        }
        |> distinctUntilChanged
    }
}
