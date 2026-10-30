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

private struct ExceptionPeer: Equatable {
    let peer: PeerEquatable
    let enabled: Bool
}

private final class Arguments {
    let context: any AccountContextProtocol
    let remove: (PeerId) -> Void
    let openInfo: (Peer) -> Void
    init(context: any AccountContextProtocol, remove: @escaping (PeerId) -> Void, openInfo: @escaping (Peer) -> Void) {
        self.context = context
        self.remove = remove
        self.openInfo = openInfo
    }
}

private struct State: Equatable {
    var peers: [ExceptionPeer]
    var loaded: Bool
}

private func _id_peer(_ peerId: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_peer_\(peerId.toInt64())")
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

    if state.peers.isEmpty {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramGhostModePerChatEmpty), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
    } else {
        for item in state.peers {
            let peer = item.peer.peer
            let viewType = bestGeneralViewType(state.peers, for: item)
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer(peer.id), equatable: InputDataEquatable(item), comparable: nil, item: { initialSize, stableId in
                return ShortPeerRowItem(initialSize, peer: peer, account: arguments.context.account, context: arguments.context, stableId: stableId, enabled: true, height: 44, photoSize: NSMakeSize(30, 30), status: item.enabled ? strings().airgramGhostModePerChatOn : strings().airgramGhostModePerChatOff, drawLastSeparator: true, inset: NSEdgeInsets(left: 20, right: 20), interactionType: .deletable(onRemove: { peerId in
                    arguments.remove(peerId)
                }, deletable: true), generalType: .none, viewType: viewType, action: {
                    arguments.openInfo(peer)
                }, contextMenuItems: {
                    return .single([ContextMenuItem(strings().confirmDelete, handler: {
                        arguments.remove(peer.id)
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)])
                })
            }))
            index += 1
        }

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().airgramGhostModePerChatNotice), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func GhostModeExceptionsController(context: any AccountContextProtocol) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State(peers: [], loaded: false)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let overrides = GhostMode.overrides
    let stored = overrides.map { (PeerId($0.key), $0.value) }

    if stored.isEmpty {
        updateState { current in
            var current = current
            current.loaded = true
            return current
        }
    } else {
        actionsDisposable.add((context.engine.data.get(EngineDataMap(stored.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0.0) })) |> deliverOnMainQueue).start(next: { peers in
            var result: [ExceptionPeer] = []
            for (peerId, enabled) in stored {
                if let peer = peers[peerId] ?? nil {
                    result.append(ExceptionPeer(peer: PeerEquatable(peer._asPeer()), enabled: enabled))
                }
            }
            result.sort(by: { $0.peer.peer.compactDisplayTitle < $1.peer.peer.compactDisplayTitle })
            updateState { current in
                var current = current
                current.peers = result
                current.loaded = true
                return current
            }
        }))
    }

    let arguments = Arguments(context: context, remove: { peerId in
        GhostMode.removeOverride(peerId: peerId)
        updateState { current in
            var current = current
            current.peers = current.peers.filter { $0.peer.peerId != peerId }
            return current
        }
    }, openInfo: { peer in
        SettingsHooks.shared.pushPeerInfo(context.bindings.rootNavigation(), context, peer.id, false)
    })

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().airgramGhostModePerChatTitle, removeAfterDisappear: false, hasDone: false)

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
}
