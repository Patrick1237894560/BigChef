import UIKit
import Vision
import CoreML
import ARKit

/// 單例，用於 2D 物件偵測並繪製在 overlayView 上
class ObjectDetector {
    static let shared = ObjectDetector()

    private weak var overlayView: UIView?
    private var boxLayers = [CAShapeLayer]()
    private var textLayers = [CATextLayer]()
    private let vnModel: VNCoreMLModel

    private init() {
        do {
            let coreMLModel = try CookDetect(configuration: MLModelConfiguration()).model
            vnModel = try VNCoreMLModel(for: coreMLModel)
        } catch {
            fatalError("❌ 無法載入 CookDetect 模型：\(error)")
        }
    }

    /// 設定用於繪製偵測結果的 Overlay
    func configure(overlay: UIView) {
        overlayView = overlay
    }

    /// 清除所有舊的繪製 Layer
    func clear() {
        boxLayers.forEach { $0.removeFromSuperlayer() }
        textLayers.forEach { $0.removeFromSuperlayer() }
        boxLayers.removeAll()
        textLayers.removeAll()
    }

    /// 偵測指定容器，回傳 (boundingRect, label, confidence) 或 nil
    func detectContainer(target container: Container,
                         in pixelBuffer: CVPixelBuffer,
                         completion: @escaping ((CGRect, String, Float)?) -> Void)
    {
        let request = VNCoreMLRequest(model: vnModel) { [weak self] request, error in
            guard let self = self else { completion(nil); return }
            if let error = error {
                print("🛑 VNCoreMLRequest 錯誤：\(error)")
                completion(nil)
                return
            }

            // 只取第一個符合 container label 的偵測結果
            let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []
            for obs in observations {
                guard let top = obs.labels.first,
                      top.identifier == container.rawValue,
                      let overlay = self.overlayView
                else { continue }

                // normalized boundingBox → overlay 坐標
                let box = obs.boundingBox
                let viewW = overlay.bounds.width
                let viewH = overlay.bounds.height

                let x = box.minX * viewW
                let w = box.width * viewW
                // Vision 的 y 原點在底部，UIKit 在頂部，所以用 (1 - maxY)
                let y = (1 - box.maxY) * viewH
                let h = box.height * viewH

                let viewRect = CGRect(x: x, y: y, width: w, height: h)

                // 在主線程繪製
                DispatchQueue.main.async {
                    self.clear()

                    // 1. Bounding box
                    let boxLayer = CAShapeLayer()
                    boxLayer.frame = overlay.bounds
                    boxLayer.path      = UIBezierPath(rect: viewRect).cgPath
                    boxLayer.strokeColor = UIColor.systemRed.cgColor
                    boxLayer.fillColor   = UIColor.clear.cgColor   // ← 清除預設黑色填充
                    boxLayer.lineWidth   = 2
                    overlay.layer.addSublayer(boxLayer)
                    self.boxLayers.append(boxLayer)

                    // 2. Label + confidence
                    let textLayer = CATextLayer()
                    textLayer.string          = "\(top.identifier) \(Int(top.confidence * 100))%"
                    textLayer.fontSize        = 14
                    textLayer.alignmentMode   = .center
                    textLayer.foregroundColor = UIColor.white.cgColor
                    textLayer.backgroundColor = UIColor.black.withAlphaComponent(0.6).cgColor
                    textLayer.frame = CGRect(
                        x: viewRect.minX,
                        y: viewRect.minY - 22,
                        width: viewRect.width,
                        height: 20
                    )
                    textLayer.contentsScale = UIScreen.main.scale
                    overlay.layer.addSublayer(textLayer)
                    self.textLayers.append(textLayer)
                }

                // 回傳畫在 overlay 上的 viewRect
                completion((viewRect, top.identifier, top.confidence))
                return
            }

            // 沒偵測到
            completion(nil)
        }

        // 記得帶上 orientation 才不會因為畫面旋轉導致框不對齊
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,  // 或根據你的 ARView 畫面方向調整
            options: [:]
        )
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("🛑 VNImageRequestHandler 錯誤：\(error)")
                completion(nil)
            }
        }
    }
}
