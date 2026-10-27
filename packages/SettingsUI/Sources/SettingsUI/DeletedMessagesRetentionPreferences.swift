import Foundation
import TelegramCore

public enum DeletedMessagesRetentionPreferences {
    private static let keepDeletedMessagesKey = "deletedMessagesRetention_keepMessages"
    private static let keepDeletedMediaKey = "deletedMessagesRetention_keepMedia"
    private static let mediaPrefetchSizeLimit: Int64 = 20 * 1024 * 1024

    public static var keepDeletedMessages: Bool {
        get {
            return UserDefaults.standard.object(forKey: keepDeletedMessagesKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keepDeletedMessagesKey)
            apply()
        }
    }

    public static var keepDeletedMedia: Bool {
        get {
            return UserDefaults.standard.object(forKey: keepDeletedMediaKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keepDeletedMediaKey)
            apply()
        }
    }

    public static func apply() {
        DeletedMessagesRetention.settings = DeletedMessagesRetentionSettings(keepDeletedMessages: keepDeletedMessages, keepDeletedMedia: keepDeletedMedia, mediaPrefetchSizeLimit: mediaPrefetchSizeLimit)
    }
}
