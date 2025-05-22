import Foundation
import simd
import RealityKit
import UIKit
import ARKit

/// 倒液體動畫
class PourLiquidAnimation: Animation {
    override var requiresContainerDetection: Bool { true }
    override var containerType: Container? { container }

    private let container: Container
    private let color: UIColor
    private let model: Entity
    private weak var arViewRef: ARView?

    init(container: Container,
         color: UIColor = .white,
         scale: Float = 1.0,
         isRepeat: Bool = false) {
        self.container = container
        self.color = color
        // 載入液體 USDZ
        let url = Bundle.main.url(forResource: "pourLiquid", withExtension: "usdz")!
        self.model = try! Entity.load(contentsOf: url)
        super.init(type: .pourLiquid, scale: scale, isRepeat: isRepeat)
    }

    /// 將模型加入 Anchor 並播放動畫
    override func applyAnimation(to anchor: AnchorEntity, on arView: ARView) {
        self.arViewRef = arView
        let entity = model.clone(recursive: true)
        if var me = entity as? ModelEntity {
            me.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
        }
        entity.scale = SIMD3<Float>(repeating: scale)
        anchor.addChild(entity)
        if let anim = entity.availableAnimations.first {
            let resource = isRepeat
                ? anim.repeat(duration: .infinity)
                : anim
            _ = entity.playAnimation(resource)
        } else {
            print("⚠️ USDZ 無可用動畫：pourLiquid")
        }
    }

    /// 更新位置：在容器框上方
    override func updateBoundingBox(rect: CGRect) {
        guard let arView = arViewRef, let anchor = anchorEntity else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let results = arView.raycast(from: center,
                                     allowing: .existingPlaneGeometry,
                                     alignment: .any)
        guard let first = results.first else { return }
        let t = first.worldTransform.columns.3
        var newPos = SIMD3<Float>(t.x, t.y+0.1, t.z-0.2)
        // 向上偏移一點，使液體落入容器上方
        newPos.y += Float(rect.height) * scale * 0.5 + 0.05
        anchor.transform.translation = newPos
    }
}
