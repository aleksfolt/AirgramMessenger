import Foundation
import Postbox
import SwiftSignalKit

public final class DeletedMessageAttribute: MessageAttribute {
    public let deletedAt: Int32

    public init(deletedAt: Int32) {
        self.deletedAt = deletedAt
    }

    required public init(decoder: PostboxDecoder) {
        self.deletedAt = decoder.decodeInt32ForKey("da", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletedAt, forKey: "da")
    }
}

public extension Message {
    var deletedAttribute: DeletedMessageAttribute? {
        return self.attributes.first(where: { $0 is DeletedMessageAttribute }) as? DeletedMessageAttribute
    }
}

public struct DeletedMessagesRetentionSettings: Equatable {
    public var keepDeletedMessages: Bool
    public var keepDeletedMedia: Bool
    public var keepMediaInPrivateChats: Bool
    public var keepMediaInGroups: Bool
    public var keepMediaInChannels: Bool
    public var mediaPrefetchSizeLimit: Int64

    public init(keepDeletedMessages: Bool, keepDeletedMedia: Bool, keepMediaInPrivateChats: Bool, keepMediaInGroups: Bool, keepMediaInChannels: Bool, mediaPrefetchSizeLimit: Int64) {
        self.keepDeletedMessages = keepDeletedMessages
        self.keepDeletedMedia = keepDeletedMedia
        self.keepMediaInPrivateChats = keepMediaInPrivateChats
        self.keepMediaInGroups = keepMediaInGroups
        self.keepMediaInChannels = keepMediaInChannels
        self.mediaPrefetchSizeLimit = mediaPrefetchSizeLimit
    }

    public static let disabled = DeletedMessagesRetentionSettings(keepDeletedMessages: false, keepDeletedMedia: false, keepMediaInPrivateChats: true, keepMediaInGroups: true, keepMediaInChannels: true, mediaPrefetchSizeLimit: 0)

    func keepsMedia(in peer: Peer) -> Bool {
        if peer is TelegramUser || peer is TelegramSecretChat {
            return self.keepMediaInPrivateChats
        } else if peer is TelegramGroup {
            return self.keepMediaInGroups
        } else if let channel = peer as? TelegramChannel {
            if case .broadcast = channel.info {
                return self.keepMediaInChannels
            } else {
                return self.keepMediaInGroups
            }
        }
        return false
    }
}

public enum DeletedMessagesRetention {
    private static let currentSettings = Atomic<DeletedMessagesRetentionSettings>(value: .disabled)

    public static var settings: DeletedMessagesRetentionSettings {
        get {
            return self.currentSettings.with { $0 }
        }
        set {
            let _ = self.currentSettings.swap(newValue)
            if MediaBox.isResourceProtected == nil {
                MediaBox.isResourceProtected = { basePath, id in
                    return DeletedMediaProtection.shared.isProtected(basePath: basePath, id: id)
                }
            }
        }
    }
}

@discardableResult
func interceptMessageDeletion(transaction: Transaction, mediaBox: MediaBox, messageId: MessageId, deletedAt: Int32) -> Bool {
    let settings = DeletedMessagesRetention.settings
    guard settings.keepDeletedMessages else {
        return false
    }
    guard let message = transaction.getMessage(messageId) else {
        return false
    }
    if message.deletedAttribute != nil {
        return true
    }
    if message.flags.contains(.Unsent) || message.flags.contains(.Failed) {
        return false
    }

    var attributes = message.attributes
    attributes.append(DeletedMessageAttribute(deletedAt: deletedAt))

    transaction.updateMessage(messageId, update: { currentMessage in
        var storeForwardInfo: StoreMessageForwardInfo?
        if let forwardInfo = currentMessage.forwardInfo {
            storeForwardInfo = StoreMessageForwardInfo(forwardInfo)
        }
        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
    })

    if settings.keepDeletedMedia {
        var resourceIds: [MediaResourceId] = []
        addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resourceIds)
        DeletedMediaProtection.shared.protect(basePath: mediaBox.basePath, ids: resourceIds)
    }
    return true
}

func releaseDeletedMessagesMedia(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) {
    var resourceIds: [MediaResourceId] = []
    for id in ids {
        if let message = transaction.getMessage(id), message.deletedAttribute != nil || message.hasPreservedViewOnceMedia {
            addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resourceIds)
        }
    }
    if !resourceIds.isEmpty {
        DeletedMediaProtection.shared.unprotect(basePath: mediaBox.basePath, ids: resourceIds)
    }
}

final class DeletedMediaProtection {
    static let shared = DeletedMediaProtection()

    private let lock = NSLock()
    private var protectedIds: [String: Set<String>] = [:]

    private func storePath(basePath: String) -> String {
        return (basePath as NSString).deletingLastPathComponent + "/deleted-media-protected"
    }

    private func loadedIds(basePath: String) -> Set<String> {
        if let ids = self.protectedIds[basePath] {
            return ids
        }
        var ids = Set<String>()
        if let data = try? String(contentsOfFile: self.storePath(basePath: basePath), encoding: .utf8) {
            for line in data.split(separator: "\n") where !line.isEmpty {
                ids.insert(String(line))
            }
        }
        self.protectedIds[basePath] = ids
        return ids
    }

    private func write(basePath: String, ids: Set<String>) {
        let contents = ids.sorted().joined(separator: "\n")
        try? contents.write(toFile: self.storePath(basePath: basePath), atomically: true, encoding: .utf8)
    }

    func isProtected(basePath: String, id: MediaResourceId) -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.loadedIds(basePath: basePath).contains(id.stringRepresentation)
    }

    func protect(basePath: String, ids: [MediaResourceId]) {
        if ids.isEmpty {
            return
        }
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        var current = self.loadedIds(basePath: basePath)
        let previousCount = current.count
        current.formUnion(ids.map { $0.stringRepresentation })
        if current.count != previousCount {
            self.protectedIds[basePath] = current
            self.write(basePath: basePath, ids: current)
        }
    }

    func unprotect(basePath: String, ids: [MediaResourceId]) {
        if ids.isEmpty {
            return
        }
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        var current = self.loadedIds(basePath: basePath)
        let previousCount = current.count
        current.subtract(ids.map { $0.stringRepresentation })
        if current.count != previousCount {
            self.protectedIds[basePath] = current
            self.write(basePath: basePath, ids: current)
        }
    }
}

enum DeletedMediaPrefetch {
    static func prefetchIfNeeded(postbox: Postbox, messageIds: [MessageId]) {
        let settings = DeletedMessagesRetention.settings
        guard settings.keepDeletedMessages, settings.keepDeletedMedia, settings.mediaPrefetchSizeLimit > 0, !messageIds.isEmpty else {
            return
        }
        let sizeLimit = settings.mediaPrefetchSizeLimit

        let _ = (postbox.transaction { transaction -> [(AnyMediaReference, TelegramMediaResource)] in
            var result: [(AnyMediaReference, TelegramMediaResource)] = []
            for id in messageIds {
                guard let peer = transaction.getPeer(id.peerId), settings.keepsMedia(in: peer) else {
                    continue
                }
                guard let message = transaction.getMessage(id), message.flags.contains(.Incoming) else {
                    continue
                }
                for media in message.media {
                    guard let (resource, size) = self.primaryResource(media: media), let size, size <= sizeLimit else {
                        continue
                    }
                    result.append((AnyMediaReference.message(message: MessageReference(message), media: media), resource))
                }
            }
            return result
        }
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { items in
            for (reference, resource) in items {
                let contentType: MediaResourceUserContentType
                if let file = reference.media as? TelegramMediaFile {
                    contentType = MediaResourceUserContentType(file: file)
                } else {
                    contentType = .image
                }
                let _ = fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: .other, userContentType: contentType, reference: .media(media: reference, resource: resource)).start()
            }
        })
    }

    private static func primaryResource(media: Media) -> (TelegramMediaResource, Int64?)? {
        if let image = media as? TelegramMediaImage {
            guard let representation = largestImageRepresentation(image.representations) else {
                return nil
            }
            return (representation.resource, representation.resource.size)
        } else if let file = media as? TelegramMediaFile {
            return (file.resource, file.size ?? file.resource.size)
        }
        return nil
    }
}
