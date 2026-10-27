import AppKit
import AVFoundation
import Observation
import SwiftUI

enum MirrorStatus: Equatable {
    case off, starting, live, denied, noCamera
}

/// Espelho: a imagem da câmera, espelhada, logo abaixo do notch, para se ver antes de uma reunião.
/// A câmera só fica ligada enquanto o espelho está aberto; nada é gravado.
@Observable final class CameraMirror {
    /// Desligado no modo `--snapshot` (não pede a câmera).
    static var cameraEnabled = true

    private(set) var isActive = false
    private(set) var status: MirrorStatus = .off
    @ObservationIgnored var onActiveChange: () -> Void = {}

    @ObservationIgnored let session = AVCaptureSession()
    /// `startRunning`/`stopRunning` bloqueiam: rodam numa fila própria, em ordem.
    @ObservationIgnored private let queue = DispatchQueue(label: "marquise.camera")
    @ObservationIgnored private var configured = false

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { return }
        isActive = true
        onActiveChange()
        guard Self.cameraEnabled else { return }
        status = .starting
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isActive else { return }
                    if granted { self.run() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        status = .off
        onActiveChange()
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    private func run() {
        queue.async { [weak self] in
            guard let self else { return }
            let ready = self.configureIfNeeded()
            if ready { self.session.startRunning() }
            DispatchQueue.main.async {
                // Fechado enquanto a câmera ligava: o stop() já está na fila, depois deste bloco.
                guard self.isActive else { return }
                self.status = ready ? .live : .noCamera
            }
        }
    }

    /// Prefere a câmera embutida (a que fica no notch) a câmeras externas ou do iPhone.
    private func configureIfNeeded() -> Bool {
        if configured { return true }
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .high
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.commitConfiguration()
        configured = true
        return true
    }

    static func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Na ilha

struct MirrorContent: View {
    let model: IslandModel

    var body: some View {
        let mirror = model.mirror
        let size = model.mirrorSize
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(mirror.status == .live ? Color.green : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(L(.cameraMirror))
                }
                Spacer(minLength: model.geometry.notchSize.width + 20)
                ControlButton(id: "mirror-close", symbol: "xmark", size: 10) { mirror.stop() }
                    .help(L(.closeMirror))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .frame(height: model.geometry.notchSize.height)
            .padding(.horizontal, 18)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06))
                if CameraMirror.cameraEnabled {
                    CameraPreview(session: mirror.session, live: mirror.status == .live)
                        .opacity(mirror.status == .live ? 1 : 0)
                        .animation(.easeOut(duration: 0.25), value: mirror.status)
                } else {
                    // Imagens de conferência: sem câmera, só o formato.
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                }
                overlay(for: mirror.status)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(width: model.mirrorPreviewSize.width, height: model.mirrorPreviewSize.height)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    @ViewBuilder private func overlay(for status: MirrorStatus) -> some View {
        switch status {
        case .off, .live:
            EmptyView()
        case .starting:
            ProgressView().controlSize(.small).tint(.white)
        case .denied:
            VStack(spacing: 10) {
                Image(systemName: "video.slash.fill").font(.system(size: 22))
                Text(L(.cameraDenied)).font(.system(size: 13, weight: .medium))
                Button(L(.openCameraSettings)) { CameraMirror.openCameraSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .foregroundStyle(.white.opacity(0.8))
        case .noCamera:
            VStack(spacing: 10) {
                Image(systemName: "video.slash").font(.system(size: 22))
                Text(L(.noCamera)).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// Prévia da câmera, espelhada como um espelho de verdade.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let live: Bool

    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView(session: session) }

    func updateNSView(_ view: CameraPreviewView, context: Context) {
        if live { view.applyMirroring() }
    }
}

final class CameraPreviewView: NSView {
    private let preview: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
        applyMirroring()
    }

    /// A conexão só existe depois que a câmera foi ligada à sessão.
    func applyMirroring() {
        guard let connection = preview.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
