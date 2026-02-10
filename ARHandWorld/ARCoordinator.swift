import SwiftUI
import RealityKit
import Vision
import AVFoundation

class ARCoordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var arView: ARView?
    var onCountUpdate: (([String: (current: Int, total: Int)]) -> Void)?
    
    private var isEffectPlaying = false
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private let captureSession = AVCaptureSession()
    private let worldAnchor = AnchorEntity(world: .zero)
    
    private var movableEntities: [ModelEntity] = []
    private var handJoints: [UUID: [VNHumanHandPoseObservation.JointName: ModelEntity]] = [:]
    private var handLines: [UUID: [Entity]] = [:]
    private var entityColorMap: [UInt64: NSColor] = [:]
    
    private var heldEntity: ModelEntity? = nil
    
    private var gameCounts: [String: (current: Int, total: Int)] = [
        "White": (0, 0), "Black": (0, 0), "Red": (0, 0), "Blue": (0, 0)
    ]
    
    private var targetAreas: [(color: NSColor, pos: SIMD3<Float>)] = []
    private let moveSpeed: Float = 0.05
    private let fingerChains: [[VNHumanHandPoseObservation.JointName]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]
    ]
    
    private func colorKey(for color: NSColor) -> String {
        if color == .white { return "White" }
        if color == .black { return "Black" }
        if color == .red { return "Red" }
        if color == .blue { return "Blue" }
        return "White"
    }
    
    func setupScene() {
        guard let arView = arView else { return }
        arView.scene.addAnchor(worldAnchor)
        
        let floor = ModelEntity(
            mesh: .generateBox(size: [100, 0.01, 100]),
            materials: [SimpleMaterial(color: NSColor(red: 0.85, green: 0.75, blue: 0.6, alpha: 1.0), isMetallic: false)]
        )
        floor.position.y = -0.2
        floor.generateCollisionShapes(recursive: true)
        floor.physicsBody = PhysicsBodyComponent(mode: .static)
        worldAnchor.addChild(floor)
        
        let areaSize: Float = 1.0
        let groundY = floor.position.y + 0.007
        let areaConfigs: [(NSColor, SIMD3<Float>)] = [
            (.white, SIMD3<Float>(-1.5, groundY, -1.6)),
            (.black, SIMD3<Float>( 1.5, groundY, -1.6)),
            (.red,   SIMD3<Float>(-1.5, groundY, 0)),
            (.blue,  SIMD3<Float>( 1.5, groundY, 0))
        ]
        
        for (color, pos) in areaConfigs {
            let area = ModelEntity(
                mesh: .generatePlane(width: areaSize, depth: areaSize, cornerRadius: 0.05),
                materials: [UnlitMaterial(color: color.withAlphaComponent(0.4))]
            )
            area.position = pos
            worldAnchor.addChild(area)
            targetAreas.append((color: color, pos: pos))
        }
    }
    
    private func internalSpawn(color: NSColor) {
        let shapes = ["box", "sphere", "cone"]
        let shape = shapes.randomElement()!
        let material = UnlitMaterial(color: color)
        let entity: ModelEntity
        switch shape {
        case "box": entity = ModelEntity(mesh: .generateBox(size: 0.05), materials: [material])
        case "sphere": entity = ModelEntity(mesh: .generateSphere(radius: 0.03), materials: [material])
        default: entity = ModelEntity(mesh: .generateCone(height: 0.07, radius: 0.035), materials: [material])
        }
        let randomX = Float.random(in: -0.5 ... 0.5)
        let randomY: Float = 0.5
        let randomZ = Float.random(in: -0.7 ... -0.3)
        entity.position = [randomX, randomY, randomZ]
        entity.generateCollisionShapes(recursive: true)
        entity.physicsBody = PhysicsBodyComponent(massProperties: .init(mass: 1), material: .default, mode: .dynamic)
        worldAnchor.addChild(entity)
        movableEntities.append(entity)
        entityColorMap[entity.id] = color
    }
    
    func spawnRandomGameObjects() {
        movableEntities.forEach { $0.removeFromParent() }
        movableEntities.removeAll()
        entityColorMap.removeAll()
        heldEntity = nil
        isEffectPlaying = false
        
        let colors: [NSColor] = [.white, .black, .red, .blue]
        var remaining = 10
        for (index, color) in colors.enumerated() {
            let count = (index == colors.count - 1) ? remaining : Int.random(in: 1...max(1, remaining - (colors.count - 1 - index)))
            gameCounts[colorKey(for: color)] = (0, count)
            remaining -= count
            for _ in 0..<count { internalSpawn(color: color) }
        }
        onCountUpdate?(gameCounts)
    }
    
    // --- エラー回避版：クリアエフェクト ---
    private func playClearEffect() {
        guard !isEffectPlaying else { return }
        isEffectPlaying = true
        
        for _ in 0..<60 {
            let confetti = ModelEntity(
                mesh: .generateBox(size: Float.random(in: 0.01...0.03)),
                materials: [UnlitMaterial(color: .orange)]
            )
            // 出現位置
            let startPos = SIMD3<Float>(Float.random(in: -0.8...0.8), -0.2, Float.random(in: -1.5...0.5))
            confetti.position = startPos
            worldAnchor.addChild(confetti)
            
            // 打ち上げ先
            var endTransform = confetti.transform
            endTransform.translation += [Float.random(in: -0.3...0.3), 1.5, Float.random(in: -0.3...0.3)]
            endTransform.rotation = simd_quatf(angle: .pi, axis: [1, 1, 1])
            
            // move(to:) の代わりに AnimationDefinition を使う方法（安全）
            confetti.move(to: endTransform, relativeTo: worldAnchor, duration: Double.random(in: 1.0...2.0), timingFunction: .easeOut)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                confetti.removeFromParent()
            }
        }
    }

    private func checkEntityStatus() {
        var changed = false
        var entitiesToRemove: [UInt64] = []
        var colorsToReplenish: [NSColor] = []
        
        for entity in movableEntities {
            guard let color = entityColorMap[entity.id] else { continue }
            let key = colorKey(for: color)
            
            if entity.position.y < -1.5 || abs(entity.position.z) > 10.0 {
                entitiesToRemove.append(entity.id)
                colorsToReplenish.append(color)
                changed = true
                continue
            }
            
            for target in targetAreas {
                if target.color == color {
                    let dist = simd_distance(entity.position, target.pos)
                    // 手が離れている(dynamic)状態でエリアに近い
                    if dist < 0.6 && entity.physicsBody?.mode == .dynamic {
                        gameCounts[key]?.current += 1
                        entitiesToRemove.append(entity.id)
                        changed = true
                        break
                    }
                }
            }
        }
        
        for id in entitiesToRemove {
            if let entity = movableEntities.first(where: { $0.id == id }) {
                if heldEntity?.id == id { heldEntity = nil }
                entity.removeFromParent()
                movableEntities.removeAll { $0.id == id }
                entityColorMap.removeValue(forKey: id)
            }
        }
        
        for color in colorsToReplenish { internalSpawn(color: color) }
        
        if changed {
            onCountUpdate?(gameCounts)
            
            // 全クリア判定
            let totalCurrent = gameCounts.values.reduce(0) { $0 + $1.current }
            let totalTarget = gameCounts.values.reduce(0) { $0 + $1.total }
            if totalCurrent >= totalTarget && totalTarget > 0 {
                playClearEffect()
            }
        }
    }
    
    func setupKeyboardMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 49 { self?.spawnRandomGameObjects() }
            else { self?.handleKeyPress(event) }
            return event
        }
    }
    
    private func handleKeyPress(_ event: NSEvent) {
        switch event.keyCode {
        case 126: worldAnchor.position.z += moveSpeed
        case 125: worldAnchor.position.z -= moveSpeed
        case 123: worldAnchor.position.x += moveSpeed
        case 124: worldAnchor.position.x -= moveSpeed
        default: break
        }
    }

    func startHandTracking() {
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        if captureSession.canAddInput(videoInput) { captureSession.addInput(videoInput) }
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "handQueue"))
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }
        DispatchQueue.global(qos: .userInitiated).async { self.captureSession.startRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([handPoseRequest])
        DispatchQueue.main.async {
            self.processHandResults(self.handPoseRequest.results ?? [])
            self.checkEntityStatus()
        }
    }

    private func processHandResults(_ observations: [VNHumanHandPoseObservation]) {
        let activeIDs = observations.map { $0.uuid }
        for id in handJoints.keys where !activeIDs.contains(id) {
            handJoints[id]?.values.forEach { $0.removeFromParent() }
            handLines[id]?.forEach { $0.removeFromParent() }
            handJoints.removeValue(forKey: id); handLines.removeValue(forKey: id)
        }
        observations.forEach { updateHand($0) }
    }

    private func updateHand(_ observation: VNHumanHandPoseObservation) {
        let id = observation.uuid
        var points: [VNHumanHandPoseObservation.JointName: SIMD3<Float>] = [:]
        var zPos: Float = -0.4
        
        if let wrist = try? observation.recognizedPoint(.wrist), let middle = try? observation.recognizedPoint(.middleMCP),
           wrist.confidence > 0.3 && middle.confidence > 0.3 {
            let dx = Float(wrist.location.x - middle.location.x), dy = Float(wrist.location.y - middle.location.y)
            zPos = -1.2 + (sqrt(dx*dx + dy*dy) * 4.0)
        }
        
        if handJoints[id] == nil { handJoints[id] = [:] }
        let allJoints: [VNHumanHandPoseObservation.JointName] = [.wrist, .thumbTip, .indexTip, .middleTip, .ringTip, .littleTip, .thumbCMC, .thumbMP, .thumbIP, .indexMCP, .indexPIP, .indexDIP, .middleMCP, .middlePIP, .middleDIP, .ringMCP, .ringPIP, .ringDIP, .littleMCP, .littlePIP, .littleDIP]
        
        for joint in allJoints {
            guard let point = try? observation.recognizedPoint(joint), point.confidence > 0.3 else { continue }
            let x = (1.0 - Float(point.location.x)) - 0.5, y = Float(point.location.y) - 0.5
            let pos = SIMD3<Float>(x * 1.4 - worldAnchor.position.x, y * 1.2, zPos - worldAnchor.position.z)
            points[joint] = pos
            if let entity = handJoints[id]?[joint] { entity.position = pos } else {
                let sphere = ModelEntity(mesh: .generateSphere(radius: 0.01), materials: [UnlitMaterial(color: .white)])
                sphere.position = pos; worldAnchor.addChild(sphere); handJoints[id]?[joint] = sphere
            }
        }
        
        handLines[id]?.forEach { $0.removeFromParent() }
        var lines: [Entity] = []
        for chain in fingerChains {
            for i in 0..<chain.count-1 {
                if let start = points[chain[i]], let end = points[chain[i+1]] {
                    let line = createLine(from: start, to: end)
                    worldAnchor.addChild(line); lines.append(line)
                }
            }
        }
        handLines[id] = lines
        
        if let index = points[.indexTip], let thumb = points[.thumbTip] {
            let pinchPos = (index + thumb) / 2
            if simd_distance(index, thumb) < 0.08 {
                if heldEntity == nil {
                    for entity in movableEntities {
                        if simd_distance(entity.position, pinchPos) < 0.12 {
                            heldEntity = entity
                            entity.physicsBody?.mode = .kinematic
                            break
                        }
                    }
                }
                if let held = heldEntity {
                    held.position = simd_mix(held.position, pinchPos, [0.7, 0.7, 0.7])
                    held.physicsMotion?.linearVelocity = [0, 0, 0]
                }
            } else {
                if let held = heldEntity {
                    held.physicsBody?.mode = .dynamic
                    heldEntity = nil
                }
            }
        }
    }

    private func createLine(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Entity {
        let distance = simd_distance(start, end)
        if distance < 0.001 { return Entity() }
        let lineEntity = ModelEntity(mesh: .generateBox(size: [0.003, 0.003, distance]), materials: [UnlitMaterial(color: .cyan.withAlphaComponent(0.5))])
        let container = Entity(); container.position = (start + end) / 2
        let direction = normalize(end - start), up = SIMD3<Float>(0, 1, 0)
        var axis = cross(up, direction)
        if length(axis) < 0.001 { axis = SIMD3<Float>(1, 0, 0) }
        container.orientation = simd_quatf(angle: acos(dot(up, direction)), axis: normalize(axis))
        container.addChild(lineEntity)
        return container
    }
}
