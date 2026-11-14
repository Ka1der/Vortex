import SwiftUI
import CoreImage
import PhotosUI
#if os(iOS)
import AVFoundation
import UIKit
#endif

/// Full-featured QR code scanner with live camera feed, photo picker decoding, and clipboard fallback
public struct QRCodeScannerView: View {
    @Environment(\.dismiss) private var dismiss

    public var onScan: (String) -> Void

    @State private var isTorchOn: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var scanErrorMessage: String? = nil
    @State private var isCameraAvailable: Bool = true
    @State private var isScanningActive: Bool = true

    public init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                #if os(iOS)
                if isCameraAvailable {
                    CameraViewRepresentable(
                        isTorchOn: $isTorchOn,
                        isScanningActive: $isScanningActive,
                        onFoundCode: { code in
                            handleScannedString(code)
                        },
                        onCameraUnavailable: {
                            isCameraAvailable = false
                        }
                    )
                    .ignoresSafeArea()

                    // Visual viewfinder target overlay
                    viewfinderOverlay
                } else {
                    fallbackView
                }
                #else
                fallbackView
                #endif

                // Top & Bottom Controls
                VStack {
                    if let error = scanErrorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Theme.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Theme.cardBackground.opacity(0.95))
                            .clipShape(Capsule())
                            .padding(.top, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer()

                    bottomControlBar
                }
                .padding()
            }
            .navigationTitle("Сканировать QR-код")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .foregroundStyle(Color.white)
                }

                #if os(iOS)
                if isCameraAvailable {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isTorchOn.toggle()
                        } label: {
                            Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isTorchOn ? Theme.orange : Color.white)
                        }
                    }
                }
                #endif
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem = newItem else { return }
                decodeFromPhotoItem(newItem)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Viewfinder Overlay

    private var viewfinderOverlay: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Theme.orange, lineWidth: 3)
                    .frame(width: 250, height: 250)
                    .background(Color.black.opacity(0.1))

                // Corner decorative brackets
                VStack {
                    HStack {
                        cornerIndicator(edge: .topLeading)
                        Spacer()
                        cornerIndicator(edge: .topTrailing)
                    }
                    Spacer()
                    HStack {
                        cornerIndicator(edge: .bottomLeading)
                        Spacer()
                        cornerIndicator(edge: .bottomTrailing)
                    }
                }
                .frame(width: 260, height: 260)
            }

            Text("Наведите камеру на QR-код узла или подписки")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .shadow(radius: 4)

            Spacer()
        }
    }

    private enum CornerEdge { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    private func cornerIndicator(edge: CornerEdge) -> some View {
        Circle()
            .fill(Theme.orange)
            .frame(width: 10, height: 10)
    }

    // MARK: - Bottom Control Bar

    private var bottomControlBar: some View {
        HStack(spacing: 16) {
            // Photos Picker
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                    Text("Из фото")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.cardBackground.opacity(0.9))
                .clipShape(Capsule())
            }

            // Paste from Clipboard
            Button {
                pasteFromClipboard()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                    Text("Из буфера")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.cardBackground.opacity(0.9))
                .clipShape(Capsule())
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Fallback View (Simulator or No Camera)

    private var fallbackView: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundStyle(Theme.secondaryText)

            Text("Камера недоступна")
                .font(.headline)
                .foregroundStyle(Color.white)

            Text("На симуляторе или устройствах без камеры вы можете выбрать скриншот QR-кода из фотогалереи или вставить ссылку из буфера обмена.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Handlers

    private func handleScannedString(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isScanningActive = false
        onScan(trimmed)
        dismiss()
    }

    private func pasteFromClipboard() {
        guard let text = ClipboardHelper.getString()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            showError("Буфер обмена пуст")
            return
        }
        handleScannedString(text)
    }

    private func decodeFromPhotoItem(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ciImage = CIImage(data: data) else {
                await MainActor.run {
                    showError("Не удалось прочитать выбранное изображение")
                }
                return
            }

            let detector = CIDetector(
                ofType: CIDetectorTypeQRCode,
                context: nil,
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
            )
            let features = detector?.features(in: ciImage) ?? []
            let qrCodes = features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }

            await MainActor.run {
                if let found = qrCodes.first, !found.isEmpty {
                    handleScannedString(found)
                } else {
                    showError("На выбранном фото QR-код не обнаружен")
                }
            }
        }
    }

    private func showError(_ text: String) {
        scanErrorMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if scanErrorMessage == text {
                scanErrorMessage = nil
            }
        }
    }
}

// MARK: - iOS Camera Representable

#if os(iOS)
private struct CameraViewRepresentable: UIViewControllerRepresentable {
    @Binding var isTorchOn: Bool
    @Binding var isScanningActive: Bool
    var onFoundCode: (String) -> Void
    var onCameraUnavailable: () -> Void

    func makeUIViewController(context: Context) -> CameraScannerViewController {
        let controller = CameraScannerViewController()
        controller.onFoundCode = onFoundCode
        controller.onCameraUnavailable = onCameraUnavailable
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraScannerViewController, context: Context) {
        uiViewController.setTorch(isTorchOn)
        uiViewController.setScanningActive(isScanningActive)
    }
}

private final class CameraScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onFoundCode: ((String) -> Void)?
    var onCameraUnavailable: (() -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isScanningEnabled: Bool = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let session = captureSession, session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
            }
        }
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            onCameraUnavailable?()
            return
        }

        let session = AVCaptureSession()

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                onCameraUnavailable?()
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onCameraUnavailable?()
                return
            }
            session.addOutput(output)

            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            self.previewLayer = layer
            self.captureSession = session

            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } catch {
            onCameraUnavailable?()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard isScanningEnabled,
              let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = first.stringValue,
              !stringValue.isEmpty else {
            return
        }

        isScanningEnabled = false
        AudioServicesPlaySystemSound(1519) // iOS Peek haptic
        onFoundCode?(stringValue)
    }

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func setScanningActive(_ active: Bool) {
        self.isScanningEnabled = active
    }
}
#endif
