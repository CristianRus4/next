import UIKit

class HapticManager {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    static func impact() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    static func taskCompletion() {
        // First, a success feedback
        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.notificationOccurred(.success)
        
        // Followed by a medium impact for more emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
            impactGenerator.impactOccurred()
        }
    }
} 