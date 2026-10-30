import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Localization
import TelegramContext
import TelegramTheme
import InAppSettings
import InputDataUI
import GeneralRows

enum AirgramPreferencesCategory {
    case profiles
    case interface
    case media

    var title: String {
        switch self {
        case .profiles:
            return strings().airgramHubCategoryProfiles
        case .interface:
            return strings().airgramHubCategoryInterface
        case .media:
            return strings().airgramHubCategoryMedia
        }
    }
}

private enum PreferenceRow: Int {
    case showProfileId
    case confirmCalls
    case secondsInMessages
    case hidePhone
    case sendHdPhotos

    var title: String {
        switch self {
        case .showProfileId:
            return strings().airgramProfilesShowProfileId
        case .confirmCalls:
            return strings().airgramProfilesCallConfirmation
        case .secondsInMessages:
            return strings().airgramInterfaceSecondsInMessages
        case .hidePhone:
            return strings().airgramInterfaceHidePhone
        case .sendHdPhotos:
            return strings().airgramMediaSendHdPhotos
        }
    }

    var isOn: Bool {
        switch self {
        case .showProfileId:
            return FastSettings.canViewPeerId
        case .confirmCalls:
            return AirgramSettings.confirmCalls
        case .secondsInMessages:
            return AirgramSettings.secondsInMessages
        case .hidePhone:
            return AirgramSettings.hidePhoneInSettings
        case .sendHdPhotos:
            return FastSettings.sendLargePhotos
        }
    }

    func set(_ value: Bool) {
        switch self {
        case .showProfileId:
            FastSettings.canViewPeerId = value
        case .confirmCalls:
            AirgramSettings.confirmCalls = value
        case .secondsInMessages:
            AirgramSettings.secondsInMessages = value
        case .hidePhone:
            AirgramSettings.hidePhoneInSettings = value
        case .sendHdPhotos:
            FastSettings.sendLargePhotos(value)
        }
    }
}

private final class Arguments {
    let context: any AccountContextProtocol
    let toggle: (PreferenceRow, Bool) -> Void
    init(context: any AccountContextProtocol, toggle: @escaping (PreferenceRow, Bool) -> Void) {
        self.context = context
        self.toggle = toggle
    }
}

private struct State: Equatable {
    var revision: Int
}

private func _id_row(_ row: PreferenceRow) -> InputDataIdentifier {
    return InputDataIdentifier("_id_row_\(row.rawValue)")
}

private func entries(_ state: State, category: AirgramPreferencesCategory, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    func append(_ rows: [PreferenceRow], header: String?, notice: String?) {
        if let header {
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(header), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
        }
        for row in rows {
            let isOn = row.isOn
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_row(row), data: .init(name: row.title, color: theme.colors.text, type: .switchable(isOn), viewType: bestGeneralViewType(rows, for: row), action: {
                arguments.toggle(row, !isOn)
            }, autoswitch: false)))
            index += 1
        }
        if let notice {
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(notice), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
        }
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    switch category {
    case .profiles:
        append([.showProfileId], header: strings().airgramProfilesHeader, notice: nil)
        append([.confirmCalls], header: nil, notice: strings().airgramProfilesCallConfirmationNotice)
    case .interface:
        append([.secondsInMessages, .hidePhone], header: strings().airgramInterfaceHeader, notice: nil)
    case .media:
        append([.sendHdPhotos], header: strings().airgramMediaHeader, notice: nil)
    }

    return entries
}

func AirgramPreferencesController(context: any AccountContextProtocol, category: AirgramPreferencesCategory) -> InputDataController {

    let initialState = State(revision: 0)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let arguments = Arguments(context: context, toggle: { row, value in
        row.set(value)
        updateState { current in
            var current = current
            current.revision += 1
            return current
        }
    })

    let signal = statePromise.get() |> map { state in
        return InputDataSignalValue(entries: entries(state, category: category, arguments: arguments))
    }

    return InputDataController(dataSignal: signal, title: category.title, removeAfterDisappear: false, hasDone: false)
}
