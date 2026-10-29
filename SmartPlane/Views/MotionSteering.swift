import Foundation
import Combine
import CoreMotion
import UIKit

@MainActor final class MotionSteering: ObservableObject {
    @Published var value: Double = 0
    @Published var available = false
    private let motion = CMMotionManager()
    private var zero: Double = 0
    private var raw: Double = 0
    func start() {
        available = motion.isDeviceMotionAvailable
        guard available else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            let gravity = data.gravity
            Task { @MainActor in
                guard let self else { return }
                let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .portrait
                switch orientation {
                case .landscapeLeft: self.raw = -gravity.y
                case .landscapeRight: self.raw = gravity.y
                case .portraitUpsideDown: self.raw = -gravity.x
                default: self.raw = gravity.x
                }
                let difference = self.raw - self.zero
                let adjusted = abs(difference) < 0.035 ? 0 : (difference - (difference > 0 ? 0.035 : -0.035)) / 0.45
                let next = min(1, max(-1, adjusted))
                self.value = self.value * 0.7 + next * 0.3
            }
        }
    }
    func calibrate() { zero = raw; value = 0 }
    func stop() { motion.stopDeviceMotionUpdates(); value = 0 }
}
