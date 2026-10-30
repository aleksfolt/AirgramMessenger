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
import LocalAnimations
import ShortPeerRow

private struct HiddenGroup: Equatable {
    let group: PeerEquatable
    let authors: [PeerEquatable]
}

private final class Arguments {
    let context: any AccountContextProtocol
    let unhide: (PeerId, PeerId) -> Void
    let openInfo: (Peer) -> Void
    init(context: any AccountContextProtocol, unhide: @escaping (PeerId, PeerId) -> Void, openInfo: @escaping (Peer) -> Void) {
        self.context = context
        self.unhide = unhide
        self.openInfo = openInfo
    }
}

private struct State: Equatable {
    var groups: [HiddenGroup]
    var loaded: Bool
}

private func _id_author(_ groupId: PeerId, _ authorId: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_author_\(groupId.toInt64())_\(authorId.toInt64())")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    if !state.loaded {
        entries.append(.loading)
        return entries
    }

    if state.groups.isEmpty {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramHiddenUsersEmpty), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
    } else {
        for item in state.groups {
            let group = item.group.peer
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(group.displayTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1

            for author in item.authors {
                let peer = author.peer
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_author(group.id, peer.id), equatable: InputDataEquatable(author), comparable: nil, item: { initialSize, stableId in
                    return ShortPeerRowItem(initialSize, peer: peer, account: arguments.context.account, context: arguments.context, stableId: stableId, enabled: true, height: 44, photoSize: NSMakeSize(30, 30), drawLastSeparator: true, inset: NSEdgeInsets(left: 20, right: 20), interactionType: .deletable(onRemove: { authorId in
                        arguments.unhide(group.id, authorId)
                    }, deletable: true), generalType: .none, viewType: bestGeneralViewType(item.authors, for: author), action: {
                        arguments.openInfo(peer)
                    }, contextMenuItems: {
                        return .single([ContextMenuItem(strings().confirmDelete, handler: {
                            arguments.unhide(group.id, peer.id)
                        }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)])
                    })
                }))
                index += 1
            }

            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        }

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramHiddenUsersNotice), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

func HiddenUsersController(context: any AccountContextProtocol) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State(groups: [], loaded: false)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let stored = AirgramSettings.hiddenAuthors
    var peerIds = Set<PeerId>()
    for (groupId, authorIds) in stored {
        peerIds.insert(PeerId(groupId))
        for authorId in authorIds {
            peerIds.insert(PeerId(authorId))
        }
    }

    if peerIds.isEmpty {
        updateState { current in
            var current = current
            current.loaded = true
            return current
        }
    } else {
        actionsDisposable.add((context.engine.data.get(EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) })) |> deliverOnMainQueue).start(next: { peers in
            var groups: [HiddenGroup] = []
            for (groupId, authorIds) in stored {
                guard let group = peers[PeerId(groupId)] ?? nil else {
                    continue
                }
                var authors: [PeerEquatable] = []
                for authorId in authorIds {
                    if let author = peers[PeerId(authorId)] ?? nil {
                        authors.append(PeerEquatable(author._asPeer()))
                    }
                }
                authors.sort(by: { $0.peer.displayTitle < $1.peer.displayTitle })
                if !authors.isEmpty {
                    groups.append(HiddenGroup(group: PeerEquatable(group._asPeer()), authors: authors))
                }
            }
            groups.sort(by: { $0.group.peer.displayTitle < $1.group.peer.displayTitle })
            updateState { current in
                var current = current
                current.groups = groups
                current.loaded = true
                return current
            }
        }))
    }

    let arguments = Arguments(context: context, unhide: { groupId, authorId in
        AirgramSettings.setAuthorHidden(false, peerId: groupId, authorId: authorId)
        updateState { current in
            var current = current
            var groups: [HiddenGroup] = []
            for item in current.groups {
                if item.group.peerId == groupId {
                    let authors = item.authors.filter { $0.peerId != authorId }
                    if !authors.isEmpty {
                        groups.append(HiddenGroup(group: item.group, authors: authors))
                    }
                } else {
                    groups.append(item)
                }
            }
            current.groups = groups
            return current
        }
    }, openInfo: { peer in
        SettingsHooks.shared.pushPeerInfo(context.bindings.rootNavigation(), context, peer.id, false)
    })

    let signal = statePromise.get() |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().airgramHiddenUsersTitle, removeAfterDisappear: false, hasDone: false)

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
}
