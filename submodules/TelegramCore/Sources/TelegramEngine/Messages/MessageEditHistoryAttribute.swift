import Foundation
import Postbox

public struct MessageEditHistoryEntry: PostboxCoding, Equatable {
    public let text: String
    public let entities: [MessageTextEntity]
    public let timestamp: Int32

    public init(text: String, entities: [MessageTextEntity], timestamp: Int32) {
        self.text = text
        self.entities = entities
        self.timestamp = timestamp
    }

    public init(decoder: PostboxDecoder) {
        self.text = decoder.decodeStringForKey("t", orElse: "")
        self.entities = decoder.decodeObjectArrayWithDecoderForKey("en")
        self.timestamp = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.text, forKey: "t")
        encoder.encodeObjectArray(self.entities, forKey: "en")
        encoder.encodeInt32(self.timestamp, forKey: "d")
    }
}

public final class MessageEditHistoryAttribute: MessageAttribute {
    public let entries: [MessageEditHistoryEntry]

    public init(entries: [MessageEditHistoryEntry]) {
        self.entries = entries
    }

    required public init(decoder: PostboxDecoder) {
        self.entries = decoder.decodeObjectArrayWithDecoderForKey("e")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObjectArray(self.entries, forKey: "e")
    }
}

public extension Message {
    var editHistoryAttribute: MessageEditHistoryAttribute? {
        return self.attributes.first(where: { $0 is MessageEditHistoryAttribute }) as? MessageEditHistoryAttribute
    }
}

func storeMessageWithUpdatedEditHistory(previousMessage: Message, updatedMessage: StoreMessage) -> StoreMessage {
    var attributes = updatedMessage.attributes
    attributes.removeAll(where: { $0 is MessageEditHistoryAttribute })

    var entries = previousMessage.editHistoryAttribute?.entries ?? []
    if previousMessage.text != updatedMessage.text {
        let versionTimestamp: Int32
        if let editedAttribute = previousMessage.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute, editedAttribute.date != 0 {
            versionTimestamp = editedAttribute.date
        } else {
            versionTimestamp = previousMessage.timestamp
        }
        let entry = MessageEditHistoryEntry(text: previousMessage.text, entities: previousMessage.textEntitiesAttribute?.entities ?? [], timestamp: versionTimestamp)
        if entries.last != entry {
            entries.append(entry)
        }
    }

    if !entries.isEmpty {
        attributes.append(MessageEditHistoryAttribute(entries: entries))
    }
    return updatedMessage.withUpdatedAttributes(attributes)
}
