import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Localization
import TelegramContext
import TelegramTheme
import InputDataUI
import GeneralRows

private enum PrivacyRow: Int {
    case ghostMode
    case hiddenUsers
}

private enum RetentionRow: Int {
    case messages
    case viewOnce
    case media
    case privateChats
    case groups
    case channels

    var title: String {
        switch self {
        case .messages:
            return strings().airgramRetentionKeepDeletedMessages
        case .viewOnce:
            return strings().airgramRetentionKeepViewOnceMedia
        case .media:
            return strings().airgramRetentionKeepDeletedMedia
        case .privateChats:
            return strings().airgramRetentionKeepDeletedMediaPrivateChats
        case .groups:
            return strings().airgramRetentionKeepDeletedMediaGroups
        case .channels:
            return strings().airgramRetentionKeepDeletedMediaChannels
        }
    }

    func isOn(_ settings: DeletedMessagesRetentionSettings) -> Bool {
        switch self {
        case .messages:
            return settings.keepDeletedMessages
        case .viewOnce:
            return AirgramSettings.keepViewOnceMedia
        case .media:
            return settings.keepDeletedMedia
        case .privateChats:
            return settings.keepMediaInPrivateChats
        case .groups:
            return settings.keepMediaInGroups
        case .channels:
            return settings.keepMediaInChannels
        }
    }

    func set(_ value: Bool) {
        switch self {
        case .messages:
            DeletedMessagesRetentionPreferences.keepDeletedMessages = value
        case .viewOnce:
            AirgramSettings.keepViewOnceMedia = value
        case .media:
            DeletedMessagesRetentionPreferences.keepDeletedMedia = value
        case .privateChats:
            DeletedMessagesRetentionPreferences.keepMediaInPrivateChats = value
        case .groups:
            DeletedMessagesRetentionPreferences.keepMediaInGroups = value
        case .channels:
            DeletedMessagesRetentionPreferences.keepMediaInChannels = value
        }
    }
}

private final class Arguments {
    let context: any AccountContextProtocol
    let openGhostMode: () -> Void
    let openHiddenUsers: () -> Void
    let toggle: (RetentionRow, Bool) -> Void
    init(context: any AccountContextProtocol, openGhostMode: @escaping () -> Void, openHiddenUsers: @escaping () -> Void, toggle: @escaping (RetentionRow, Bool) -> Void) {
        self.context = context
        self.openGhostMode = openGhostMode
        self.openHiddenUsers = openHiddenUsers
        self.toggle = toggle
    }
}

private struct State: Equatable {
    var retention: DeletedMessagesRetentionSettings
    var viewOnce: Bool
    var ghostModeEnabled: Bool
}

private let _id_ghost_mode = InputDataIdentifier("_id_ghost_mode")
private let _id_hidden_users = InputDataIdentifier("_id_hidden_users")

private func _id_retention(_ row: RetentionRow) -> InputDataIdentifier {
    return InputDataIdentifier("_id_retention_\(row.rawValue)")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramFeaturesGhostPrivacy), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let privacyRows: [PrivacyRow] = [.ghostMode, .hiddenUsers]
    for row in privacyRows {
        switch row {
        case .ghostMode:
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_ghost_mode, data: .init(name: strings().airgramGhostModeTitle, color: theme.colors.text, type: .nextContext(state.ghostModeEnabled ? strings().airgramGhostModeOn : strings().airgramGhostModeOff), viewType: bestGeneralViewType(privacyRows, for: row), action: arguments.openGhostMode)))
        case .hiddenUsers:
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_hidden_users, data: .init(name: strings().airgramHiddenUsersTitle, color: theme.colors.text, type: .next, viewType: bestGeneralViewType(privacyRows, for: row), action: arguments.openHiddenUsers)))
        }
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramFeaturesRetention), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    var rows: [RetentionRow] = [.messages, .viewOnce, .media]
    if state.retention.keepDeletedMedia {
        rows += [.privateChats, .groups, .channels]
    }
    for row in rows {
        let isOn = row.isOn(state.retention)
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_retention(row), data: .init(name: row.title, color: theme.colors.text, type: .switchable(isOn), viewType: bestGeneralViewType(rows, for: row), action: {
            arguments.toggle(row, !isOn)
        })))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func AirgramFeaturesController(context: any AccountContextProtocol) -> InputDataController {

    let initialState = State(retention: DeletedMessagesRetention.settings, viewOnce: AirgramSettings.keepViewOnceMedia, ghostModeEnabled: GhostMode.settings.isFullyEnabled)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let arguments = Arguments(context: context, openGhostMode: {
        context.bindings.rootNavigation().push(GhostModeController(context: context))
    }, openHiddenUsers: {
        context.bindings.rootNavigation().push(HiddenUsersController(context: context))
    }, toggle: { row, value in
        row.set(value)
        updateState { current in
            var current = current
            current.retention = DeletedMessagesRetention.settings
            current.viewOnce = AirgramSettings.keepViewOnceMedia
            return current
        }
    })

    let signal = statePromise.get() |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments), animated: false)
    }

    let controller = InputDataController(dataSignal: signal, title: strings().airgramHubCategoryAirgram, removeAfterDisappear: false, hasDone: false)

    controller.didAppear = { _ in
        updateState { current in
            var current = current
            current.ghostModeEnabled = GhostMode.settings.isFullyEnabled
            return current
        }
    }

    return controller
}
