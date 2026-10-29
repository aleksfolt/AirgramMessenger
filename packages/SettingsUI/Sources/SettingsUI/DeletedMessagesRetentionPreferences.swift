import Foundation
import TelegramCore

public enum DeletedMessagesRetentionPreferences {
    private static let keepDeletedMessagesKey = "deletedMessagesRetention_keepMessages"
    private static let keepDeletedMediaKey = "deletedMessagesRetention_keepMedia"
    private static let keepMediaInPrivateChatsKey = "deletedMessagesRetention_mediaPrivateChats"
    private static let keepMediaInGroupsKey = "deletedMessagesRetention_mediaGroups"
    private static let keepMediaInChannelsKey = "deletedMessagesRetention_mediaChannels"
    private static let mediaPrefetchSizeLimit: Int64 = 20 * 1024 * 1024

    private static func bool(_ key: String) -> Bool {
        return UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    private static func set(_ value: Bool, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
        apply()
    }

    public static var keepDeletedMessages: Bool {
        get {
            return bool(keepDeletedMessagesKey)
        }
        set {
            set(newValue, for: keepDeletedMessagesKey)
        }
    }

    public static var keepDeletedMedia: Bool {
        get {
            return bool(keepDeletedMediaKey)
        }
        set {
            set(newValue, for: keepDeletedMediaKey)
        }
    }

    public static var keepMediaInPrivateChats: Bool {
        get {
            return bool(keepMediaInPrivateChatsKey)
        }
        set {
            set(newValue, for: keepMediaInPrivateChatsKey)
        }
    }

    public static var keepMediaInGroups: Bool {
        get {
            return bool(keepMediaInGroupsKey)
        }
        set {
            set(newValue, for: keepMediaInGroupsKey)
        }
    }

    public static var keepMediaInChannels: Bool {
        get {
            return bool(keepMediaInChannelsKey)
        }
        set {
            set(newValue, for: keepMediaInChannelsKey)
        }
    }

    public static func apply() {
        DeletedMessagesRetention.settings = DeletedMessagesRetentionSettings(
            keepDeletedMessages: keepDeletedMessages,
            keepDeletedMedia: keepDeletedMedia,
            keepMediaInPrivateChats: keepMediaInPrivateChats,
            keepMediaInGroups: keepMediaInGroups,
            keepMediaInChannels: keepMediaInChannels,
            mediaPrefetchSizeLimit: mediaPrefetchSizeLimit
        )
    }
}
