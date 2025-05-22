import RealityKit
import ARKit
import UIKit
/// AnimationFactory：根據 AnimationType 與參數回傳對應的 Animation 子類
struct AnimationFactory {
    static func make(type: AnimationType, params: AnimationParams) -> Animation {
        switch type {
             case .putIntoContainer:
                 return PutIntoContainerAnimation(
                 ingredientName: params.ingredient ?? "",
                 container: params.container ?? .pan,
                 scale: 0.05,
                 isRepeat: true
                 )
             case .stir:
                 return StirAnimation(
                     container: params.container ?? .pan,
                     scale: 0.2,
                     isRepeat: true
                 )
            case .pourLiquid:
                let uiColor = UIColor(named: params.color ?? "") ?? .white
                return PourLiquidAnimation(
                    container: params.container ?? .pan,
                    color: uiColor,
                    scale: 0.05,
                    isRepeat: true
                )
            case .flipPan ,.flip:
                return FlipAnimation(
                    container: params.container ?? .pan,
                    scale: 0.5,
                    isRepeat:true
                )
            case .countdown:
                return CountdownAnimation(
                    minutes: Int(params.time ?? 0),      // ← 強制轉型為 Int
                    container: params.container ?? .pan,
                    scale: 0.05,
                    isRepeat: true
                )            /*
              case .temperature:
              return TemperatureAnimation(
              temperatureValue: params.temperature ?? 0,
              container: params.container ?? .pan,
              scale: params.scale,
              isRepeat: params.isRepeat
              )*/
            case .flame:
                let level = FlameLevel(rawValue: params.flameLevel ?? "") ?? .medium
                return FlameAnimation(
                        level: level,
                        container: params.container ?? .pan,
                        scale: 0.005,
                        isRepeat: true
                )
            case .sprinkle:
                return SprinkleAnimation(
                    container: params.container ?? .pan,
                    scale: 0.05,
                    isRepeat: true
                )
            /*
              case .torch:
              return TorchAnimation(
              position: params.coordinate ?? [0,0,0],
              scale: params.scale,
              isRepeat: params.isRepeat
              )*/
            case .cut:
            let coords = params.coordinate ?? [0.7, -0.8, 0.95]
                let pos = SIMD3<Float>(coords[0], coords[1], coords[2])
                return CutAnimation(
                    position: pos,
                    scale: 0.02,
                    isRepeat: true
                )            /*
              case .peel:
              return PeelAnimation(
              position: params.coordinate ?? [0,0,0],
              scale: params.scale,
              isRepeat: params.isRepeat
              )*/
            /*
            case .flip:
                // 翻面動作，與炒鍋翻鍋共用 FlipAnimation 亦可拆分為專屬類別
                return FlipAnimation(
                    container: params.container ?? .pan,
                    scale: 0.5,
                    isRepeat: true
                )*//*
              case .beatEgg:
              return BeatEggAnimation(
              container: params.container ?? .pan,
              scale: params.scale,
              isRepeat: params.isRepeat
              )*/
        default:
            fatalError("未支援的 AnimationType：\(type)")
        }
    }
}
