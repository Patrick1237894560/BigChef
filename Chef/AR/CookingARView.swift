import SwiftUI
import RealityKit
import ARKit
import UIKit
import simd
import Combine

/// 用於顯示 RealityKit ARView 並疊加 2D 偵測框、把框心映射到假設深度之 3D 座標
struct CookingARView: UIViewRepresentable {
    @Binding var step: String
    var externalSession: ARSession?    // ⬅️ 新增外部傳入的 session

    private let manager = AnimationManager()
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIView(context: Context) -> ARView {
//        let arView = ARView(frame: .zero)
//        arView.session = externalSession ?? arView.session  // 若有就用外部 session
//        arView.automaticallyConfigureSession = false
//        
//        // 啟動 AR Session
//        let config = ARWorldTrackingConfiguration()
//        arView.session.run(config, options: [])  // ✅ 不要再 run 第二次，如果已經有外部 session
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = true  // ✅ 讓 RealityKit 自己接管 ARSession

        arView.session.delegate = context.coordinator
        
        
        print("✅ ARView initialized: \(arView)")
        arView.debugOptions = [.showFeaturePoints]
        arView.backgroundColor = .red  // 幫助你確認是不是被遮住了

        // 加 overlay 用來畫 2D bounding box
        let overlay = UIView(frame: arView.bounds)
        overlay.backgroundColor = .clear
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(overlay)
        
        context.coordinator.arView  = arView
        context.coordinator.overlay = overlay
        ObjectDetector.shared.configure(overlay: overlay)
        
        return arView
    }
    
    @MainActor
    func updateUIView(_ uiView: ARView, context: Context) {
        
        // 1. step 为空时不处理
        guard !step.isEmpty else { return }
        
        // 2. 同一步骤，只需 reset detection state
        if context.coordinator.lastStep == step {
            context.coordinator.resetDetectionState()
            return
        }
        
        // 3. 新步骤：清场并重置
        context.coordinator.lastStep      = step
        context.coordinator.lastAnimation = nil
        context.coordinator.resetDetectionState()
        ObjectDetector.shared.clear()
        uiView.scene.anchors.removeAll()
        
        // 4. 调 Gemini 拿 animation，存入 Coordinator
        Task { @MainActor in
            guard let (type, params) = await manager.selectTypeAndParameters(
                for: step,
                from: uiView
            ) else { return }
            let animation = AnimationFactory.make(type: type, params: params)
            context.coordinator.lastAnimation = animation
            // 如果不需要容器偵測，直接播放動畫
            if !animation.requiresContainerDetection {
                context.coordinator.playAnimationLoop()
            }
            // 待检测到目标后，由 Coordinator 触发 playAnimationLoop()
        }
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, ARSessionDelegate {
        private var parent: CookingARView?
        weak var arView: ARView?
        weak var overlay: UIView?
        
        var lastStep: String?
        var lastAnimation: Animation?
        
        /// 由 Coordinator 自己绘制的 boxLayers，要在每帧前清除
        private var boxLayers: [CAShapeLayer] = []
        
        /// 目标持续在画面里的状态
        private var isDetectionActive  = false
        /// 是否正在播放动画
        private var isAnimationPlaying = false
        
        /// 内建动画播放完成订阅
        private var playbackSubscription: Cancellable?
        /// 静态模型 1s 后移除任务
        private var staticRemovalWorkItem: DispatchWorkItem?
        
        init(_ parent: CookingARView) {
            self.parent = parent
        }
        
        /// 重置状态：停止循环、取消订阅、清任务
        func resetDetectionState() {
            isDetectionActive   = false
            isAnimationPlaying  = false
            playbackSubscription?.cancel()
            staticRemovalWorkItem?.cancel()
            playbackSubscription    = nil
            staticRemovalWorkItem   = nil
        }
        
        /// ARSession 每帧回调
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            
            guard
                let animation = lastAnimation,
                animation.requiresContainerDetection,
                let container = animation.containerType,
                let overlay   = overlay,
                let arView    = arView
            else { return }
            
            // 先清掉 ObjectDetector 画的框
            ObjectDetector.shared.clear()
            // 再清掉 Coordinator 自己画的框
            boxLayers.forEach { $0.removeFromSuperlayer() }
            boxLayers.removeAll()
            
            // 跑 2D 物件偵測
            ObjectDetector.shared.detectContainer(
                target: container,
                in: frame.capturedImage
            ) { [weak self] result in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch result {
                    // 只有置信度 > 0.8 才认为检测到
                    case let (rect, _, confidence)? where confidence > 0.8:
                        self.isDetectionActive = true
                        
                        // 1. 在 overlay 上绘制红框（ObjectDetector 也会绘一次）
                        let boxLayer = CAShapeLayer()
                        boxLayer.frame       = overlay.bounds
                        boxLayer.path        = UIBezierPath(rect: rect).cgPath
                        boxLayer.strokeColor = UIColor.systemRed.cgColor
                        boxLayer.fillColor   = UIColor.clear.cgColor
                        boxLayer.lineWidth   = 2
                        //overlay.layer.addSublayer(boxLayer)
                        self.boxLayers.append(boxLayer)
                        
                        // 2. 将 2D 中心点发射 raycast，定位 3D 点
                        let center2D = CGPoint(x: rect.midX, y: rect.midY)
                        if let query = arView.makeRaycastQuery(
                                from: center2D,
                                allowing: .estimatedPlane,
                                alignment: .any
                           ),
                           let rayResult = arView.session.raycast(query).first {
                            let t = rayResult.worldTransform.columns.3
                            animation.updatePosition(SIMD3<Float>(t.x, t.y, t.z))
                        }
                        
                        // 3. 如果尚未播放，就启动循环播放
                        if !self.isAnimationPlaying {
                            self.playAnimationLoop()
                        }
                        
                    default:
                        // 无检测到或置信度低：停止继续检测，但等待当前播放完毕后再移除 Anchor
                        self.isDetectionActive = false
                    }
                }
            }
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("❌ ARSession 錯誤：\(error.localizedDescription)")
            // 嘗試重啟
            let config = ARWorldTrackingConfiguration()
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
        
        /// 检测到后，循环播放：播放完 → 移除 → 若检测仍在继续 → 再播
        @MainActor
        func playAnimationLoop() {
            guard
                !isAnimationPlaying,
                let arView    = arView,
                let animation = lastAnimation
            else { return }

            // 若此動畫不需容器偵測，直接設為已啟用狀態
            if !animation.requiresContainerDetection {
                isDetectionActive = true
            }

            // 沒有偵測也不啟動
            guard isDetectionActive else { return }
            
            isAnimationPlaying = true
            playbackSubscription?.cancel()
            staticRemovalWorkItem?.cancel()
            
            // 播放／挂载 Anchor
            animation.play(on: arView, reuseAnchor: false)
            
            guard let anchor = animation.anchorEntity else { return }
            let modelEntity = anchor.children.first
            
            if let model = modelEntity, !model.availableAnimations.isEmpty {
                if animation.type == .putIntoContainer {
                    NotificationCenter.default.addObserver(forName: Notification.Name("PutIntoContainerAnimationCompleted"), object: nil, queue: .main) { [weak self] _ in
                        guard let self = self else { return }
                        arView.scene.removeAnchor(anchor)
                        self.isAnimationPlaying = false
                        if self.isDetectionActive {
                            self.playAnimationLoop()
                        }
                    }
                    return
                }
                // 内建动画：监听 PlaybackCompleted
                playbackSubscription = arView.scene
                    .subscribe(to: AnimationEvents.PlaybackCompleted.self) { [weak self] event in
                        guard let self = self else { return }
                        if event.playbackController.entity == model {
                            arView.scene.removeAnchor(anchor)
                            self.isAnimationPlaying = false
                            if self.isDetectionActive {
                                self.playAnimationLoop()
                            }
                            self.playbackSubscription?.cancel()
                            self.playbackSubscription = nil
                        }
                    }
            } else {
                // 无内建动画：显示 1 秒后移除
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    arView.scene.removeAnchor(anchor)
                    self.isAnimationPlaying = false
                    if self.isDetectionActive {
                        self.playAnimationLoop()
                    }
                }
                staticRemovalWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
            }
        }
    }
}

// MARK: - 需要检测容器的动画类型
extension AnimationType {
    var requiresContainerDetection: Bool {
        switch self {
            case .putIntoContainer, .stir, .pourLiquid, .flipPan,
                 .flip, .countdown, .temperature, .flame,
                 .sprinkle, .beatEgg:
                return true
            default:
                return false
        }
    }
}
