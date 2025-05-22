import RealityKit
import UIKit
import ARKit

/// 翻面（Flip）動畫：當偵測到指定容器後，執行翻面動畫
class FlipAnimation: Animation {
    /// 以 Entity 描述，可容納帶骨骼或普通模型
    private let model: Entity
    /// 指定要偵測的容器
    private let container: Container
    private var boundingBoxRect: CGRect?

    override var requiresContainerDetection: Bool { true }
    override var containerType: Container? { container }

    /// 現在把 container 拿進來，初始化時設定
    init(container: Container,
         scale: Float = 1,
         isRepeat: Bool = false) {
        self.container = container

        // 載入 flip.usdz
        guard let url = Bundle.main.url(forResource: "flip", withExtension: "usdz") else {
            fatalError("❌ 找不到 flip.usdz")
        }
        do {
            model = try Entity.load(contentsOf: url)
        } catch {
            fatalError("❌ 無法載入 flip.usdz：\(error)")
        }

        super.init(type: .flip, scale: scale, isRepeat: isRepeat)
    }

    /// 將模型加入 Anchor 並播放內建動畫
    override func applyAnimation(to anchor: AnchorEntity, on arView: ARView) {
        // 將整個模型（group）加入 anchor
        anchor.addChild(model)
        
        // 調整整組模型的位置：往鏡頭前方 0.5 米之外，並向右下移動
        model.setPosition(SIMD3<Float>(0.6, -1, -3), relativeTo: anchor)
        
        // 套用縮放到整組模型
        model.setScale(SIMD3<Float>(repeating: scale), relativeTo: anchor)
        
        // 直接播放 model 上所有動畫
        if let animation = model.availableAnimations.first {
            model.playAnimation(animation, transitionDuration: 0.0, startsPaused: false)
        }
        
    }

    /// 每次 2D 偵測框更新時，儲存以做對齊
    override func updateBoundingBox(rect: CGRect) {
        boundingBoxRect = rect
    }

    
}
