import AudioToolbox
import Foundation

/// Orbit's short completion sounds (ios/App/Sounds, made by scripts/make_sounds.py; Windows plays the
/// same notes live). System sounds follow the silent switch and never interrupt other audio.
enum Sounds {
    enum Kind: String { case tick = "orbit-tick", day = "orbit-day", badge = "orbit-badge" }
    private static var ids: [Kind: SystemSoundID] = [:]
    static var enabled: Bool { UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true }

    static func play(_ kind: Kind) {
        guard enabled else { return }
        if ids[kind] == nil, let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "wav") {
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError { ids[kind] = id }
        }
        if let id = ids[kind] { AudioServicesPlaySystemSound(id) }
    }
}
