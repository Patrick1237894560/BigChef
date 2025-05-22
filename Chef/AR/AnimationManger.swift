import Foundation
import GoogleGenerativeAI
import simd
import UIKit
import RealityKit


class AnimationManager {
    typealias AnimationManger = AnimationManager   // backward‑compat

    private static let sharedModel: GenerativeModel = {
        let apiKey = Bundle.main
            .object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String ?? ""
        return GenerativeModel(name: "gemini-2.0-flash-lite", apiKey: apiKey)
    }()

    private let model: GenerativeModel

    /// 最後一次向 Gemini 發請求的時間
    private var lastGenerateTime: CFTimeInterval = 0
    /// 兩次請求最小間隔（秒）
    private let minInterval: CFTimeInterval = 0.35

    init() {
        self.model = AnimationManager.sharedModel
    }
    
    private var lastStep: String?
    private var lastResult: (AnimationType, AnimationParams)?
    
        struct CombinedResult: Codable {
        var type: String
        var ingredient: String?
        var color: String?
        var coordinate: [Float]?
        var time: Float?
        var temperature: Float?
        var flameLevel: String?
        var container: String?
    }
    
    @MainActor func selectTypeAndParameters(for step: String, from arView: ARView) async -> (AnimationType, AnimationParams)? {
        if step == lastStep, let cached = lastResult {
            return cached
        }
        // 若兩次請求間隔過短，直接回傳快取
        let now = CACurrentMediaTime()
        if now - lastGenerateTime < minInterval, let cached = lastResult {
            return cached
        }
        lastGenerateTime = now
        // Build choice list
        let choices = AnimationType.allCases.map { $0.rawValue }.joined(separator: ", ")
        let containerChoices = Container.allCases.map { $0.rawValue }.joined(separator: ", ")
        let screenshot: UIImage = await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image ?? UIImage())
            }
        }
        let promptText = """
        請根據以下烹飪步驟 "\(step)"，從 [\(choices)] 中選擇最符合的 rawValue，並回傳以下 JSON 結構：
        {
          "type": "選中的 rawValue",
          "container": "選中的 container（\(containerChoices)）",
          "coordinate": [x, y, z] 或 null,
          "ingredient": "食材或 null",
          "color": "顏色或 null",
          "time": 時間數值或 null,
          "temperature": 溫度數值或 null,
          "flameLevel": "small/medium/large 或 null"
        }
        依不同動畫類型，以下欄位為必須提供：
        - putIntoContainer: ingredient, container        
        - stir: container
        - pourLiquid: container, color
        - flipPan: container
        - countdown: time, container
        - temperature: temperature, container
        - flame: container, flameLevel
        - sprinkle: container
        - torch: coordinate
        - cut: coordinate
        - peel: coordinate
        - flip: container
        - beatEgg: container
        請確保所有回傳的文字值ingredient 使用英文開頭小寫。
        請確保回傳的 JSON 包含上述必需欄位，並移除所有程式碼區塊標記。
        請確保回傳的 JSON 嚴格符合 iOS Codable 規範，不含 Optional 或其他與 JSON 格式無關的標識。
        範例格式：
        ```json
        {
          "type": "pourLiquid",
          "container": "pan",
          "coordinate": null,
          "ingredient": null,
          "color": "brown",
          "time": null,
          "temperature": null,
          "flameLevel": null
        }
        ```
        """
        print("📨 發送 Prompt：\(promptText)")
        let textPart = ModelContent.Part.text(promptText)
        let imagePart = ModelContent.Part.png(screenshot.pngData()!)
        do {
            let response = try await model.generateContent(textPart, imagePart)
            var raw = response.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            raw = raw
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .replacingOccurrences(of: "`", with: "")
            if let start = raw.firstIndex(where: { $0 == "{" }) {
                raw = String(raw[start...])
            }
            guard let data = raw.data(using: .utf8) else {
                print("⚠️ 無法將回傳轉為 Data：\(raw)")
                return nil
            }
            let decoder = JSONDecoder()
            let result = try decoder.decode(CombinedResult.self, from: data)
            guard let animationType = AnimationType(rawValue: result.type) else {
                print("❌ 無效的 AnimationType：\(result.type)")
                return nil
            }
            let container = result.container.flatMap { Container(rawValue: $0) }
            let params = AnimationParams(
                coordinate:  result.coordinate,
                container:   container,
                ingredient:  result.ingredient,
                color:       result.color,
                time:        result.time,
                temperature: result.temperature,
                flameLevel:  result.flameLevel
            )
            lastStep = step
            lastResult = (animationType, params)
            do {
                let jsonData = try JSONEncoder().encode(params)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("✅ 選擇類型：\(animationType)，參數 JSON：\(jsonString)")
                } else {
                    print("✅ 選擇類型：\(animationType)，參數無法轉成 JSON")
                }
            } catch {
                print("✅ 選擇類型：\(animationType)，參數 JSON 編碼失敗：\(error)")
            }
            return (animationType, params)
        } catch {
            print("❌ 解析參數失敗：\(error)")
            return nil
        }
    }
}
struct AnimationParams: Codable {
    let coordinate: [Float]?
    let container: Container?
    let ingredient: String?
    let color: String?
    let time: Float?
    let temperature: Float?
    let flameLevel: String?
}
