import AVFoundation
import SwiftUI
import UIKit

/// 自定义相机的一次拍摄结果。原始 `data` 可直接交给 `FoodImagePreparer`。
struct CapturedFoodPhoto: Identifiable {
    let captureID: UUID
    let data: Data

    var id: UUID { captureID }
}

enum FastFoodCameraError: LocalizedError, Equatable {
    case permissionDenied
    case cameraUnavailable
    case configurationFailed(String)
    case captureFailed(String)
    case invalidPhotoData

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有相机权限"
        case .cameraUnavailable:
            return "当前设备没有可用相机"
        case .configurationFailed:
            return "相机启动失败"
        case .captureFailed:
            return "拍照失败"
        case .invalidPhotoData:
            return "照片读取失败"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "请在系统设置中允许「减重助手」使用相机。"
        case .cameraUnavailable:
            return "模拟器不提供相机，请在真机拍摄，或改用相册照片。"
        case .configurationFailed(let message), .captureFailed(let message):
            return message
        case .invalidPhotoData:
            return "请保持镜头稳定后重新拍摄。"
        }
    }

    var needsSettings: Bool {
        self == .permissionDenied
    }
}

/// 轻点快门后直接返回照片，不经过系统 UIImagePickerController 的“使用照片”确认页。
struct FastFoodCameraView: View {
    let onCapture: (CapturedFoodPhoto) -> Void
    let onCancel: () -> Void
    var guidanceText = "对准食物，轻点拍摄"
    var captureAccessibilityLabel = "拍摄食物照片"
    var captureAccessibilityHint = "拍摄后立即开始识别，不再显示确认页面"

    @StateObject private var camera = FastFoodCameraController()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var videoRotationAngle: CGFloat = 90

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if camera.isReady {
                    FastFoodCameraPreview(
                        session: camera.session,
                        rotationAngle: videoRotationAngle
                    )
                    .ignoresSafeArea()
                } else if camera.error == nil {
                    ProgressView("正在打开相机…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }

                cameraControls

                if let error = camera.error {
                    errorPanel(error)
                }
            }
            .onAppear {
                updateRotationAngle()
                camera.start()
            }
            .onChange(of: geometry.size) { _, _ in
                updateRotationAngle()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    updateRotationAngle()
                    camera.start()
                } else {
                    camera.stop()
                }
            }
            .onDisappear {
                camera.stop()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    private var cameraControls: some View {
        VStack {
            HStack {
                Button(action: onCancel) {
                    Text("取消")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                .disabled(camera.isCapturing)
                .opacity(camera.isCapturing ? 0.55 : 1)
                .accessibilityHint("退出拍照")

                Spacer()

                Button {
                    camera.toggleFlash()
                } label: {
                    Image(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(camera.isFlashOn ? .yellow : .white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .disabled(!camera.hasFlash || !camera.isReady)
                .opacity(camera.hasFlash ? 1 : 0.45)
                .accessibilityLabel(
                    interfaceLocalized(
                        camera.isFlashOn ? "关闭闪光灯" : "打开闪光灯",
                        locale: locale
                    )
                )
                .accessibilityHint(
                    camera.hasFlash
                        ? ""
                        : interfaceLocalized("当前相机没有闪光灯", locale: locale)
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer()

            if camera.error == nil {
                Text(interfaceLocalized(
                    camera.isCapturing ? "正在拍摄…" : guidanceText,
                    locale: locale
                ))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.bottom, 20)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    camera.capture(rotationAngle: videoRotationAngle) { result in
                        switch result {
                        case .success(let photo):
                            UINotificationFeedbackGenerator()
                                .notificationOccurred(.success)
                            onCapture(photo)
                        case .failure:
                            break
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 5)
                            .frame(width: 78, height: 78)
                        Circle()
                            .fill(.white)
                            .frame(width: 64, height: 64)
                            .scaleEffect(camera.isCapturing ? 0.84 : 1)
                    }
                }
                .disabled(!camera.isReady || camera.isCapturing)
                .opacity(camera.isReady ? 1 : 0.5)
                .accessibilityLabel(
                    interfaceLocalized(captureAccessibilityLabel, locale: locale)
                )
                .accessibilityHint(
                    interfaceLocalized(captureAccessibilityHint, locale: locale)
                )
                .padding(.bottom, 24)
            }
        }
    }

    private func errorPanel(_ error: FastFoodCameraError) -> some View {
        VStack(spacing: 14) {
            Image(systemName: error.needsSettings ? "camera.badge.ellipsis" : "camera.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white)

            Text(interfaceLocalized(
                error.errorDescription ?? "相机不可用",
                locale: locale
            ))
                .font(.headline)
                .foregroundStyle(.white)

            if let suggestion = error.recoverySuggestion {
                Text(interfaceLocalized(suggestion, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }

            if error.needsSettings {
                Button("打开系统设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else {
                        return
                    }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
            } else if error != .cameraUnavailable {
                Button("重试") {
                    camera.retry()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("取消", action: onCancel)
                .foregroundStyle(.white)
        }
        .padding(24)
        .frame(maxWidth: 330)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    private func updateRotationAngle() {
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        guard let orientation = activeScene?.interfaceOrientation else { return }
        videoRotationAngle = Self.rotationAngle(for: orientation)
    }

    private static func rotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            return 0
        case .landscapeRight:
            return 180
        default:
            return 90
        }
    }
}

private final class FastFoodCameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isReady = false
    @Published private(set) var isCapturing = false
    @Published private(set) var hasFlash = false
    @Published private(set) var isFlashOn = false
    @Published private(set) var error: FastFoodCameraError?

    private let sessionQueue = DispatchQueue(
        label: "com.lukegogogo.WeightCoach.fast-food-camera",
        qos: .userInitiated
    )
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var configuredDeviceHasFlash = false
    private var pendingCaptures: [Int64: PendingCapture] = [:]
    private let pendingCaptureLock = NSLock()
    private let lifecycleLock = NSLock()
    private var wantsRunning = false
    private var lifecycleGeneration = 0

    private struct PendingCapture {
        let captureID: UUID
        let lifecycleGeneration: Int
        let completion: (Result<CapturedFoodPhoto, FastFoodCameraError>) -> Void
    }

    func start() {
        let generation = activateLifecycle()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.startIfAuthorized(generation: generation)
        }
    }

    func stop() {
        invalidateLifecycle()
        pendingCaptureLock.lock()
        pendingCaptures.removeAll()
        pendingCaptureLock.unlock()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isReady = false
                self.isCapturing = false
            }
        }
    }

    func retry() {
        error = nil
        start()
    }

    func toggleFlash() {
        guard hasFlash else { return }
        isFlashOn.toggle()
    }

    func capture(
        rotationAngle: CGFloat,
        completion: @escaping (Result<CapturedFoodPhoto, FastFoodCameraError>) -> Void
    ) {
        guard isReady,
              !isCapturing,
              let generation = activeLifecycleGeneration() else { return }

        isCapturing = true
        error = nil
        let captureID = UUID()
        let flashMode: AVCaptureDevice.FlashMode = isFlashOn ? .on : .off

        sessionQueue.async { [weak self] in
            guard let self,
                  self.isLifecycleActive(generation),
                  self.isConfigured,
                  self.session.isRunning else {
                DispatchQueue.main.async {
                    guard let self,
                          self.isLifecycleActive(generation) else { return }
                    self.finishCapture(
                        result: .failure(.cameraUnavailable),
                        completion: completion
                    )
                }
                return
            }

            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }

            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed
            if self.configuredDeviceHasFlash {
                settings.flashMode = flashMode
            }

            self.pendingCaptureLock.lock()
            self.pendingCaptures[settings.uniqueID] = PendingCapture(
                captureID: captureID,
                lifecycleGeneration: generation,
                completion: completion
            )
            self.pendingCaptureLock.unlock()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func startIfAuthorized(generation: Int) {
        guard isLifecycleActive(generation) else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart(generation: generation)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.sessionQueue.async {
                    guard self.isLifecycleActive(generation) else { return }
                    if granted {
                        self.configureAndStart(generation: generation)
                    } else {
                        self.publish(error: .permissionDenied, generation: generation)
                    }
                }
            }
        case .denied, .restricted:
            publish(error: .permissionDenied, generation: generation)
        @unknown default:
            publish(error: .permissionDenied, generation: generation)
        }
    }

    private func configureAndStart(generation: Int) {
        guard isLifecycleActive(generation) else { return }
        if isConfigured {
            startSessionIfNeeded(generation: generation)
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) ?? AVCaptureDevice.default(for: .video) else {
            publish(error: .cameraUnavailable, generation: generation)
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
                publish(
                    error: .configurationFailed("相机输入或照片输出不可用，请重新打开拍照页。"),
                    generation: generation
                )
                return
            }

            session.addInput(input)
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed
            configuredDeviceHasFlash = device.hasFlash
            isConfigured = true

            DispatchQueue.main.async {
                self.hasFlash = device.hasFlash
                if !device.hasFlash {
                    self.isFlashOn = false
                }
                self.error = nil
            }
        } catch {
            publish(
                error: .configurationFailed(error.localizedDescription),
                generation: generation
            )
            return
        }

        // startRunning 必须在 commitConfiguration 之后；defer 会在本方法返回时提交。
        sessionQueue.async { [weak self] in
            self?.startSessionIfNeeded(generation: generation)
        }
    }

    private func startSessionIfNeeded(generation: Int) {
        guard isConfigured,
              isLifecycleActive(generation) else { return }
        if !session.isRunning {
            session.startRunning()
        }
        DispatchQueue.main.async {
            guard self.isLifecycleActive(generation) else { return }
            self.error = nil
            self.isReady = true
        }
    }

    private func publish(error: FastFoodCameraError, generation: Int? = nil) {
        if let generation {
            guard isLifecycleActive(generation) else { return }
        }
        DispatchQueue.main.async {
            if let generation, !self.isLifecycleActive(generation) { return }
            self.error = error
            self.isReady = false
            self.isCapturing = false
        }
    }

    private func activateLifecycle() -> Int {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        wantsRunning = true
        lifecycleGeneration += 1
        return lifecycleGeneration
    }

    private func invalidateLifecycle() {
        lifecycleLock.lock()
        wantsRunning = false
        lifecycleGeneration += 1
        lifecycleLock.unlock()
    }

    private func activeLifecycleGeneration() -> Int? {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return wantsRunning ? lifecycleGeneration : nil
    }

    private func isLifecycleActive(_ generation: Int) -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return wantsRunning && lifecycleGeneration == generation
    }

    private func finishCapture(
        result: Result<CapturedFoodPhoto, FastFoodCameraError>,
        completion: @escaping (Result<CapturedFoodPhoto, FastFoodCameraError>) -> Void
    ) {
        isCapturing = false
        if case .failure(let failure) = result {
            error = failure
        }
        completion(result)
    }
}

extension FastFoodCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let settingsID = photo.resolvedSettings.uniqueID
        pendingCaptureLock.lock()
        let pendingCapture = pendingCaptures.removeValue(forKey: settingsID)
        pendingCaptureLock.unlock()
        guard let pendingCapture else { return }

        let result: Result<CapturedFoodPhoto, FastFoodCameraError>
        if let error {
            result = .failure(.captureFailed(error.localizedDescription))
        } else if let data = photo.fileDataRepresentation(), !data.isEmpty {
            result = .success(
                CapturedFoodPhoto(
                    captureID: pendingCapture.captureID,
                    data: data
                )
            )
        } else {
            result = .failure(.invalidPhotoData)
        }

        guard isLifecycleActive(pendingCapture.lifecycleGeneration) else { return }
        DispatchQueue.main.async {
            guard self.isLifecycleActive(pendingCapture.lifecycleGeneration) else { return }
            self.finishCapture(
                result: result,
                completion: pendingCapture.completion
            )
        }
    }
}

private struct FastFoodCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let rotationAngle: CGFloat

    func makeUIView(context: Context) -> FastFoodCameraPreviewUIView {
        let view = FastFoodCameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.updateRotationAngle(rotationAngle)
        return view
    }

    func updateUIView(_ uiView: FastFoodCameraPreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.updateRotationAngle(rotationAngle)
    }
}

private final class FastFoodCameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    func updateRotationAngle(_ angle: CGFloat) {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(angle) else {
            return
        }
        connection.videoRotationAngle = angle
    }
}
