import Foundation
import Postbox
import SwiftSignalKit

public struct GhostModeSettings: Equatable {
    public var sendReadMessages: Bool
    public var sendReadMedia: Bool
    public var sendOnlinePackets: Bool
    public var sendTyping: Bool
    public var sendViews: Bool

    public init(sendReadMessages: Bool, sendReadMedia: Bool, sendOnlinePackets: Bool, sendTyping: Bool, sendViews: Bool) {
        self.sendReadMessages = sendReadMessages
        self.sendReadMedia = sendReadMedia
        self.sendOnlinePackets = sendOnlinePackets
        self.sendTyping = sendTyping
        self.sendViews = sendViews
    }

    public static let disabled = GhostModeSettings(sendReadMessages: true, sendReadMedia: true, sendOnlinePackets: true, sendTyping: true, sendViews: true)
    public static let enabled = GhostModeSettings(sendReadMessages: false, sendReadMedia: false, sendOnlinePackets: false, sendTyping: false, sendViews: false)

    public var isFullyEnabled: Bool {
        return self == GhostModeSettings.enabled
    }
}

public enum GhostModeSignal {
    case readMessages
    case readMedia
    case onlinePackets
    case typing
    case views
}

public enum GhostMode {
    private struct State {
        var settings: GhostModeSettings
        var overrides: [Int64: Bool]
    }

    private static let defaultsPrefix = "ghostMode_"
    private static let overridesKey = "ghostMode_overrides"

    private static func defaultsBool(_ name: String) -> Bool {
        return UserDefaults.standard.object(forKey: self.defaultsPrefix + name) as? Bool ?? true
    }

    private static let state: Atomic<State> = {
        let settings = GhostModeSettings(
            sendReadMessages: GhostMode.defaultsBool("sendReadMessages"),
            sendReadMedia: GhostMode.defaultsBool("sendReadMedia"),
            sendOnlinePackets: GhostMode.defaultsBool("sendOnlinePackets"),
            sendTyping: GhostMode.defaultsBool("sendTyping"),
            sendViews: GhostMode.defaultsBool("sendViews")
        )
        var overrides: [Int64: Bool] = [:]
        if let stored = UserDefaults.standard.dictionary(forKey: GhostMode.overridesKey) as? [String: Bool] {
            for (key, value) in stored {
                if let peerId = Int64(key) {
                    overrides[peerId] = value
                }
            }
        }
        return Atomic<State>(value: State(settings: settings, overrides: overrides))
    }()

    public static var settings: GhostModeSettings {
        get {
            return self.state.with { $0.settings }
        }
        set {
            let _ = self.state.modify { current in
                var current = current
                current.settings = newValue
                return current
            }
            let defaults = UserDefaults.standard
            defaults.set(newValue.sendReadMessages, forKey: self.defaultsPrefix + "sendReadMessages")
            defaults.set(newValue.sendReadMedia, forKey: self.defaultsPrefix + "sendReadMedia")
            defaults.set(newValue.sendOnlinePackets, forKey: self.defaultsPrefix + "sendOnlinePackets")
            defaults.set(newValue.sendTyping, forKey: self.defaultsPrefix + "sendTyping")
            defaults.set(newValue.sendViews, forKey: self.defaultsPrefix + "sendViews")
        }
    }

    public static var overrides: [Int64: Bool] {
        return self.state.with { $0.overrides }
    }

    public static func override(peerId: PeerId) -> Bool? {
        return self.state.with { $0.overrides[peerId.toInt64()] }
    }

    public static func isActive(peerId: PeerId) -> Bool {
        return !self.sends(.readMessages, peerId: peerId)
    }

    public static func setActive(_ active: Bool, peerId: PeerId) {
        let followsGlobal = active == !self.settings.sendReadMessages
        let key = peerId.toInt64()
        let updated = self.state.modify { current in
            var current = current
            if followsGlobal {
                current.overrides.removeValue(forKey: key)
            } else {
                current.overrides[key] = active
            }
            return current
        }
        self.persistOverrides(updated.overrides)
    }

    public static func removeOverride(peerId: PeerId) {
        let key = peerId.toInt64()
        let updated = self.state.modify { current in
            var current = current
            current.overrides.removeValue(forKey: key)
            return current
        }
        self.persistOverrides(updated.overrides)
    }

    private static func persistOverrides(_ overrides: [Int64: Bool]) {
        var stored: [String: Bool] = [:]
        for (key, value) in overrides {
            stored[String(key)] = value
        }
        UserDefaults.standard.set(stored, forKey: self.overridesKey)
    }

    public static func sends(_ signal: GhostModeSignal, peerId: PeerId?) -> Bool {
        let current = self.state.with { $0 }
        if signal != .onlinePackets, let peerId, let override = current.overrides[peerId.toInt64()] {
            return !override
        }
        switch signal {
        case .readMessages:
            return current.settings.sendReadMessages
        case .readMedia:
            return current.settings.sendReadMedia
        case .onlinePackets:
            return current.settings.sendOnlinePackets
        case .typing:
            return current.settings.sendTyping
        case .views:
            return current.settings.sendViews
        }
    }
}
