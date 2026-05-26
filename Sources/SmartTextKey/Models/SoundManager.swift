import AppKit

public final class SoundManager: Sendable {
    public static let shared = SoundManager()
    
    private init() {}
    
    public enum SoundType: Sendable {
        case start
        case success
        case failure
        
        var systemSoundName: String {
            switch self {
            case .start: return "Purr"
            case .success: return "Glass"
            case .failure: return "Basso"
            }
        }
    }
    
    /// Plays the requested sound type asynchronously on the main actor if sound effects are enabled.
    public func play(_ type: SoundType) {
        Task { @MainActor in
            guard AppSettings.shared.enableSoundEffects else { return }
            if let sound = NSSound(named: type.systemSoundName) {
                sound.play()
            }
        }
    }
}
