import Foundation
import simd
import RealityKit
import ARKit

/// 撒調味料動畫
class SprinkleAnimation: Animation {
    override var requiresContainerDetection: Bool { true }
    override var containerType: Container? { container }

    private let container: Container
    private let model: Entity
    private weak var arViewRef: ARView?

    init(container: Container,
         scale: Float = 1.0,
         isRepeat: Bool = false) {
        self.container = container
        // 載入 sprinkle USDZ
        let url = Bundle.main.url(forResource: "sprinkle", withExtension: "usdz")!
        self.model = try! Entity.load(contentsOf: url)
        super.init(type: .sprinkle, scale: scale, isRepeat: isRepeat)
    }

    /// 加入 Anchor 並播放動畫
    override func applyAnimation(to anchor: AnchorEntity, on arView: ARView) {
        self.arViewRef = arView
        let entity = model.clone(recursive: true)
        entity.scale = SIMD3<Float>(repeating: scale)
        anchor.addChild(entity)
        if let animation = entity.availableAnimations.first {
            let resource = isRepeat
                ? animation.repeat(duration: .infinity)
                : animation
            _ = entity.playAnimation(resource)
        } else {
            print("⚠️ USDZ 無可用動畫：sprinkle")
        }
    }

    /// 更新位置：在容器框上方均勻撒落
    override func updateBoundingBox(rect: CGRect) {
        guard let arView = arViewRef, let anchor = anchorEntity else { return }
        // 將框中心轉 raycast 至世界座標
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let results = arView.raycast(from: center,
                                     allowing: .existingPlaneGeometry,
                                     alignment: .any)
        guard let first = results.first else { return }
        let t = first.worldTransform.columns.3
        var newPos = SIMD3<Float>(t.x, t.y, t.z)
        newPos.x += 0.2  // 往右方偏移 0.1 米
        // 向上偏移，使調味料位於框上方
        newPos.y += Float(rect.height) * scale * 0.5 + 0.05
        anchor.transform.translation = newPos
    }
}
