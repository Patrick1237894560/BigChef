import Foundation
import simd
import RealityKit

/// 切割動作動畫
class CutAnimation: Animation {
    override var requiresContainerDetection: Bool { false }
    override var containerType: Container? { nil }

    private let cutPosition: SIMD3<Float>
    private let model: Entity

    /// 初始化時載入模型與設定位置
    init(position: SIMD3<Float>, scale: Float = 1.0, isRepeat: Bool = false) {
        self.cutPosition = position
        // 從資源載入 USDZ
        let url = Bundle.main.url(forResource: "cut", withExtension: "usdz")!
        self.model = try! Entity.load(contentsOf: url)
        super.init(type: .cut, scale: scale, isRepeat: isRepeat)
    }

    /// 將模型加到 Anchor 並執行動畫
    override func applyAnimation(to anchor: AnchorEntity, on arView: ARView) {
        let entity = model.clone(recursive: true)
        entity.scale = SIMD3<Float>(repeating: scale)
        anchor.transform.translation = cutPosition
        anchor.addChild(entity)

        if let animation = entity.availableAnimations.first {
            let resource = isRepeat
                ? animation.repeat(duration: .infinity)
                : animation
            _ = entity.playAnimation(resource)
            print("✅ 動畫播放開始：")
        } else {
            print("⚠️ USDZ 無可用動畫：cut")
        }
    }
}
