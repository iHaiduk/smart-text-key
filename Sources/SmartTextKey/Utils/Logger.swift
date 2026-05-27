import Foundation
import os

public enum AppLogger {
    public static let subsystem = "com.ihaiduk.SmartTextKey"
    
    public static let general = Logger(subsystem: subsystem, category: "General")
    public static let pipeline = Logger(subsystem: subsystem, category: "Pipeline")
    public static let aiService = Logger(subsystem: subsystem, category: "AIService")
    public static let keychain = Logger(subsystem: subsystem, category: "Keychain")
    public static let history = Logger(subsystem: subsystem, category: "History")
    public static let shortcut = Logger(subsystem: subsystem, category: "Shortcut")
    public static let clipboard = Logger(subsystem: subsystem, category: "Clipboard")
}
