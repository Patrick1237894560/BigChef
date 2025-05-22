import Foundation
import simd
import RealityKit
import ARKit

/// 火焰等級
enum FlameLevel: String {
    case small, medium, large
}

/// 根據容器框顯示火焰動畫（仅静态显示，不播放动画）
class FlameAnimation: Animation {
    override var requiresContainerDetection: Bool { true }
    override var containerType: Container? { container }

    private let container: Container
    private let level: FlameLevel
    private let model: Entity
    private weak var arViewRef: ARView?

    init(level: FlameLevel = .medium,
         container: Container,
         scale: Float = 1.0,
         isRepeat: Bool = false) {
        self.container = container
        self.level = level
        // 载入对应等级的火焰 USDZ
        let resourceName = "flame_\(level.rawValue)"
        let url = Bundle.main.url(forResource: resourceName, withExtension: "usdz")!
        self.model = try! Entity.load(contentsOf: url)
        super.init(type: .flame, scale: scale, isRepeat: isRepeat)
    }

    /// 将模型加入 Anchor，但不执行任何内部动画，只做静态显示
    override func applyAnimation(to anchor: AnchorEntity, on arView: ARView) {
        self.arViewRef = arView

        let entity = model.clone(recursive: true)
        entity.scale = SIMD3<Float>(repeating: scale)
        anchor.addChild(entity)
        // 不调用 playAnimation——只做静态展示
    }

    /// 更新位置：将火焰置于容器框下方
    override func updateBoundingBox(rect: CGRect) {
        guard let arView = arViewRef, let anchor = anchorEntity else { return }
        // 框中心转为世界坐标
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let results = arView.raycast(from: center,
                                     allowing: .existingPlaneGeometry,
                                     alignment: .any)
        guard let first = results.first else { return }
        let t = first.worldTransform.columns.3
        var newPos = SIMD3<Float>(t.x, t.y, t.z)
        newPos.x += 0.5 // 向右偏移 0.1 米
        newPos.y -= 0.5  // 向下偏移 0.1 米
        newPos.z -= 0.5
        // 向下偏移一点，使火焰位于框底下方
        newPos.y += -Float(rect.height) * 0.5 * scale
        anchor.transform.translation = newPos
    }
}
