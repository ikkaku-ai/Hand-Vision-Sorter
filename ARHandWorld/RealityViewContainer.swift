import SwiftUI
import RealityKit

struct RealityViewContainer: NSViewRepresentable {
    @Binding var counts: [String: (current: Int, total: Int)]
    
    func makeNSView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.environment.background = .color(NSColor(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0))
        
        context.coordinator.arView = arView
        context.coordinator.onCountUpdate = { newCounts in
            DispatchQueue.main.async {
                self.counts = newCounts
            }
        }
        
        context.coordinator.setupScene()
        context.coordinator.startHandTracking()
        context.coordinator.setupKeyboardMonitoring()
        // 初回生成
        context.coordinator.spawnRandomGameObjects()
        
        return arView
    }
    
    func updateNSView(_ nsView: ARView, context: Context) {}
    func makeCoordinator() -> ARCoordinator { ARCoordinator() }
}
