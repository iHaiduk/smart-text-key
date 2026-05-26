import Foundation

public struct HistoryItem: Identifiable, Sendable, Equatable {
    public let id: Int64
    public let timestamp: Date
    public let promptTitle: String
    public let inputText: String
    public let outputText: String
    
    public init(id: Int64, timestamp: Date, promptTitle: String, inputText: String, outputText: String) {
        self.id = id
        self.timestamp = timestamp
        self.promptTitle = promptTitle
        self.inputText = inputText
        self.outputText = outputText
    }
}
