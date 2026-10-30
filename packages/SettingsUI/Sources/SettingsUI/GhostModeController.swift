import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import InputDataUI
import GeneralRows

private enum GhostModeSwitch: Int, CaseIterable {
    case master
    case readMessages
    case readMedia
    case online
    case typing
    case views

    var title: String {
        switch self {
        case .master:
            return strings().airgramGhostModeToggle
        case .readMessages:
            return strings().airgramGhostModeDontReadMessages
        case .readMedia:
            return strings().airgramGhostModeDontReadMedia
        case .online:
            return strings().airgramGhostModeDontSendOnline
        case .typing:
            return strings().airgramGhostModeDontSendTyping
        case .views:
            return strings().airgramGhostModeDontCountViews
        }
    }

    func isOn(_ settings: GhostModeSettings) -> Bool {
        switch self {
        case .master:
            return settings.isFullyEnabled
        case .readMessages:
            return !settings.sendReadMessages
        case .readMedia:
            return !settings.sendReadMedia
        case .online:
            return !settings.sendOnlinePackets
        case .typing:
            return !settings.sendTyping
        case .views:
            return !settings.sendViews
        }
    }

    func applying(_ enabled: Bool, to settings: GhostModeSettings) -> GhostModeSettings {
        var settings = settings
        switch self {
        case .master:
            settings = enabled ? GhostModeSettings.enabled : GhostModeSettings.disabled
        case .readMessages:
            settings.sendReadMessages = !enabled
        case .readMedia:
            settings.sendReadMedia = !enabled
        case .online:
            settings.sendOnlinePackets = !enabled
        case .typing:
            settings.sendTyping = !enabled
        case .views:
            settings.sendViews = !enabled
        }
        return settings
    }
}

private final class Arguments {
    let context: any AccountContextProtocol
    let toggle: (GhostModeSwitch, Bool) -> Void
    let openExceptions: () -> Void
    init(context: any AccountContextProtocol, toggle: @escaping (GhostModeSwitch, Bool) -> Void, openExceptions: @escaping () -> Void) {
        self.context = context
        self.toggle = toggle
        self.openExceptions = openExceptions
    }
}

private struct State: Equatable {
    var settings: GhostModeSettings
    var exceptionsCount: Int
}

private func _id_switch(_ value: GhostModeSwitch) -> InputDataIdentifier {
    return InputDataIdentifier("_id_switch_\(value.rawValue)")
}
private let _id_exceptions = InputDataIdentifier("_id_exceptions")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_switch(.master), data: .init(name: GhostModeSwitch.master.title, color: theme.colors.text, type: .switchable(GhostModeSwitch.master.isOn(state.settings)), viewType: .singleItem, action: {
        arguments.toggle(.master, !GhostModeSwitch.master.isOn(state.settings))
    }, autoswitch: false)))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramGhostModeNotice), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramGhostModeDetailsHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let details: [GhostModeSwitch] = [.readMessages, .readMedia, .online, .typing, .views]
    for detail in details {
        let isOn = detail.isOn(state.settings)
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_switch(detail), data: .init(name: detail.title, color: theme.colors.text, type: .switchable(isOn), viewType: bestGeneralViewType(details, for: detail), action: {
            arguments.toggle(detail, !isOn)
        }, autoswitch: false)))
        index += 1
    }

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramGhostModeDetailsNotice), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    if state.exceptionsCount > 0 {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_exceptions, data: .init(name: strings().airgramGhostModePerChatTitle, color: theme.colors.text, type: .nextContext("\(state.exceptionsCount)"), viewType: .singleItem, action: arguments.openExceptions)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func GhostModeController(context: any AccountContextProtocol) -> InputDataController {

    let initialState = State(settings: GhostMode.settings, exceptionsCount: GhostMode.overrides.count)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let arguments = Arguments(context: context, toggle: { value, enabled in
        let updated = value.applying(enabled, to: GhostMode.settings)
        GhostMode.settings = updated
        updateState { current in
            var current = current
            current.settings = updated
            return current
        }
    }, openExceptions: {
        context.bindings.rootNavigation().push(GhostModeExceptionsController(context: context))
    })

    let signal = statePromise.get() |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().airgramGhostModeTitle, removeAfterDisappear: false, hasDone: false)

    controller.didAppear = { _ in
        updateState { current in
            var current = current
            current.settings = GhostMode.settings
            current.exceptionsCount = GhostMode.overrides.count
            return current
        }
    }

    return controller
}
