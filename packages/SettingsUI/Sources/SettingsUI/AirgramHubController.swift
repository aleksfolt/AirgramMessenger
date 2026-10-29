import Cocoa
import TGUIKit
import SwiftSignalKit
import Localization
import TelegramContext
import TelegramTheme
import InputDataUI
import GeneralRows

private enum HubLink: CaseIterable {
    case channel
    case chats
    case site

    var title: String {
        switch self {
        case .channel:
            return strings().airgramHubLinkChannel
        case .chats:
            return strings().airgramHubLinkChats
        case .site:
            return strings().airgramHubLinkSite
        }
    }

    var url: String {
        switch self {
        case .channel:
            return "https://t.me/airgram"
        case .chats:
            return "https://t.me/airgramchat"
        case .site:
            return "https://airgram.app"
        }
    }
}

private final class Arguments {
    let context: any AccountContextProtocol
    let openAirgram: () -> Void
    let openLink: (HubLink) -> Void
    init(context: any AccountContextProtocol, openAirgram: @escaping () -> Void, openLink: @escaping (HubLink) -> Void) {
        self.context = context
        self.openAirgram = openAirgram
        self.openLink = openLink
    }
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_category_airgram = InputDataIdentifier("_id_category_airgram")

private func _id_link(_ link: HubLink) -> InputDataIdentifier {
    return InputDataIdentifier("_id_link_\(link.url)")
}

private func entries(arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    let version = AirgramBranding.versionText
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: InputDataEquatable(version), comparable: nil, item: { initialSize, stableId in
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: arguments.context, sticker: nil, text: .initialize(string: strings().airgramHubCategoryAirgram, color: theme.colors.text, font: .bold(22)), infoText: .initialize(string: version, color: theme.colors.grayText, font: .normal(.text)), stickerSize: NSMakeSize(80, 80), image: AirgramBranding.logo(size: NSMakeSize(80, 80), cornerRadius: 18), viewType: .legacy)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramHubCategories), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_category_airgram, data: .init(name: strings().airgramHubCategoryAirgram, color: theme.colors.text, icon: AirgramBranding.airgramCategoryIcon, type: .next, viewType: .singleItem, action: arguments.openAirgram)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramHubLinks), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let links = HubLink.allCases
    for link in links {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_link(link), data: .init(name: link.title, color: theme.colors.text, type: .next, viewType: bestGeneralViewType(links, for: link), action: {
            arguments.openLink(link)
        })))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func AirgramHubController(context: any AccountContextProtocol) -> InputDataController {

    let arguments = Arguments(context: context, openAirgram: {
        context.bindings.rootNavigation().push(AirgramFeaturesController(context: context))
    }, openLink: { link in
        if let url = URL(string: link.url) {
            NSWorkspace.shared.open(url)
        }
    })

    let statePromise = ValuePromise(true, ignoreRepeated: true)

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { _ in
        return InputDataSignalValue(entries: entries(arguments: arguments))
    }

    return InputDataController(dataSignal: signal, title: strings().airgramPreferences)
}
