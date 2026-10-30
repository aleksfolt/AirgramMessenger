import Foundation
import Postbox

public class PreservedViewOnceMediaAttribute: MessageAttribute {
    public init() {
    }

    required public init(decoder: PostboxDecoder) {
    }

    public func encode(_ encoder: PostboxEncoder) {
    }
}

func shouldPreserveViewOnceMedia(message: Message) -> Bool {
    guard AirgramSettings.keepViewOnceMedia else {
        return false
    }
    return message.minAutoremoveOrClearTimeout == viewOnceTimeout
}

public extension Message {
    var hasPreservedViewOnceMedia: Bool {
        return self.attributes.contains(where: { $0 is PreservedViewOnceMediaAttribute })
    }
}

func tagsForPreservedViewOnceMedia(message: Message, attributes: [MessageAttribute], media: [Media]) -> (MessageTags, GlobalMessageTags) {
    let entities = (attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities
    return tagsForStoreMessage(
        incoming: message.flags.contains(.Incoming),
        attributes: attributes,
        media: media,
        textEntities: entities,
        isPinned: message.tags.contains(.pinned)
    )
}

func storeMessageWithPreservedViewOnceMedia(previousMessage: Message, updatedMessage: StoreMessage) -> StoreMessage {
    guard previousMessage.hasPreservedViewOnceMedia || shouldPreserveViewOnceMedia(message: previousMessage) else {
        return updatedMessage
    }
    guard updatedMessage.media.contains(where: { $0 is TelegramMediaExpiredContent }) else {
        return updatedMessage
    }
    guard !previousMessage.media.isEmpty, !previousMessage.media.contains(where: { $0 is TelegramMediaExpiredContent }) else {
        return updatedMessage
    }

    var attributes = updatedMessage.attributes
    if !attributes.contains(where: { $0 is PreservedViewOnceMediaAttribute }) {
        attributes.append(PreservedViewOnceMediaAttribute())
    }
    let media = previousMessage.media
    let (tags, globalTags) = tagsForPreservedViewOnceMedia(message: previousMessage, attributes: attributes, media: media)
    return StoreMessage(
        id: updatedMessage.id,
        customStableId: updatedMessage.customStableId,
        globallyUniqueId: updatedMessage.globallyUniqueId,
        groupingKey: updatedMessage.groupingKey,
        threadId: updatedMessage.threadId,
        timestamp: updatedMessage.timestamp,
        flags: updatedMessage.flags,
        tags: tags,
        globalTags: globalTags,
        localTags: updatedMessage.localTags,
        forwardInfo: updatedMessage.forwardInfo,
        authorId: updatedMessage.authorId,
        text: updatedMessage.text,
        attributes: attributes,
        media: media
    )
}
