import AppKit

@MainActor
protocol HapticProviding: AnyObject {
    func performHoverFeedback()
}

@MainActor
final class HapticService: HapticProviding {
    func performHoverFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
}
