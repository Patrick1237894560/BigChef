import Foundation
import simd
import RealityKit
import ARKit

/// 定義容器類型
enum Container: String, CaseIterable, Codable {
    case airFryer, bowl, microWaveOven, oven, pan, plate, riceCooker, soupPot
}

/// 食材掉入容器動畫
class PutIntoContainerAnimation: Animation {
    override var requiresContainerDetection: Bool { true }
    override var containerType: Container? { container }

    // USDZ 實體快取
    private static let cache = LRUCache<URL, Entity>(capacity: 10)

    private let container: Container
    private let model: Entity
    private weak var arViewRef: ARView?

    var containerPosition: SIMD3<Float>? {
        return _containerPosition
    }

    private var _containerPosition: SIMD3<Float>?

    init(ingredientName: String,
         container: Container,
         scale: Float = 1.0,
         isRepeat: Bool = false) {
        // 先載入模型，若 ingredientName.usdz 不存在，則載入 fallback 並加上 3D 文字
        if let url = Bundle.main.url(forResource: ingredientName, withExtension: "usdz") {
            if let cached = PutIntoContainerAnimation.cache[url] {
                model = cached
            } else if let loaded = try? Entity.load(contentsOf: url) {
                PutIntoContainerAnimation.cache[url] = loaded
                model = loaded
            } else {
                // 載入預設模型 ingredient.usdz 並加上文字
                let fallbackURL = Bundle.main.url(forResource: "ingredient", withExtension: "usdz")!
                let baseModel = try! Entity.load(contentsOf: fallbackURL)

                let textMesh = MeshResource.generateText(
                    ingredientName,
                    extrusionDepth: 0.01,
                    font: .systemFont(ofSize: 0.1),
                    containerFrame: .zero,
                    alignment: .center,
                    lineBreakMode: .byWordWrapping
                )
                let material = SimpleMaterial(color: .white, isMetallic: false)
                let textEntity = ModelEntity(mesh: textMesh, materials: [material])
                let bounds = baseModel.visualBounds(relativeTo: baseModel)
                let topY = bounds.max.y
                textEntity.position = SIMD3<Float>(0, topY + 0.1, 0)
                textEntity.scale = SIMD3<Float>(repeating: scale)
                baseModel.addChild(textEntity)

                model = baseModel
            }
        } else {
            // ingredientName.usdz 不存在，嘗試載入 ingredient.usdz
            if let fallbackURL = Bundle.main.url(forResource: "ingredient", withExtension: "usdz"),
               let baseModel = try? Entity.load(contentsOf: fallbackURL) {
                model = baseModel
            } else {
                // 若 fallback 也不存在：以純文字模型代替
                let textMesh = MeshResource.generateText(
                    ingredientName,
                    extrusionDepth: 0.01,
                    font: .systemFont(ofSize: 0.2),
                    containerFrame: .zero,
                    alignment: .center,
                    lineBreakMode: .byWordWrapping
                )
                let material = SimpleMaterial(color: .white, isMetallic: false)
                let textEntity = ModelEntity(mesh: textMesh, materials: [material])
                model = textEntity
            }
        }
        self.container = container
        super.init(type: .putIntoContainer, scale: scale, isRepeat: isRepeat)
    }

    /// 把模型加到 Anchor 並播放
    override func applyAnimation(to anchor: AnchorEntity, on arView: ARView) {
        arViewRef = arView
        let entity = model.clone(recursive: true)
        print("🔍 applyAnimation: cloned entity children count:", entity.children.count)
        entity.scale = SIMD3<Float>(repeating: scale)
        entity.children.forEach { child in
            print("🔍 child entity:", child, "name:", child.name)
        }
        anchor.addChild(entity)

        // 初始位置：從高處開始
        var startPosition = anchor.transform.translation
        startPosition.y += 0.2
        entity.position = startPosition

        // 掉落到容器最後偵測到的位置，讓掉落更明顯
        guard let endPosition = containerPosition else { return }
        _ = entity.move(to: Transform(translation: endPosition),
                        relativeTo: anchor,
                        duration: 2.0,
                        timingFunction: .easeIn)
        // 在移動動畫預計結束後發送通知
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: Notification.Name("PutIntoContainerAnimationCompleted"), object: self)
        }
    }
    /// 更新位置：在容器框上方執行掉落
    override func updateBoundingBox(rect: CGRect) {
        guard let arView = arViewRef, let anchor = anchorEntity else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let results = arView.raycast(from: center,
                                     allowing: .existingPlaneGeometry,
                                     alignment: .any)
        guard let first = results.first else { return }
        let t = first.worldTransform.columns.3
        var newPos = SIMD3<Float>(t.x, t.y, t.z)
        // 向上偏移使食材在容器上方
        newPos.y += Float(rect.height) * scale * 0.3
        anchor.transform.translation = newPos
        self._containerPosition = newPos
    }
}
