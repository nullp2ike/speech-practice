import UIKit

final class HapticManager {
    static let shared = HapticManager()

    // MARK: - Cached Generators

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    private init() {}

    func playNavigationFeedback() {
        mediumImpact.impactOccurred()
    }

    func playSegmentCompleteFeedback() {
        notificationGenerator.notificationOccurred(.success)
    }

    func playSelectionFeedback() {
        selectionGenerator.selectionChanged()
    }

    func playErrorFeedback() {
        notificationGenerator.notificationOccurred(.error)
    }

    func playLightImpact() {
        lightImpact.impactOccurred()
    }

    func playHeavyImpact() {
        heavyImpact.impactOccurred()
    }
}
