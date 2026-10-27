import AppKit
import AVFoundation
import IOKit
import Observation
import SwiftUI

enum MirrorStatus: Equatable {
    case off, starting, live, denied, noCamera
    /// A câmera do Mac não está disponível, mas há um iPhone por perto: pergunta se pode usá-lo.
    case offerIPhone
}

/// Espelho: a imagem da câmera, espelhada, logo abaixo do notch, para se ver antes de uma reunião.
/// A câmera só fica ligada enquanto o espelho está aberto; nada é gravado.
@Observable final class CameraMirror {
    /// Desligado no modo `--snapshot` (não pede a câmera).
    static var cameraEnabled = true

    private(set) var isActive = false
    private(set) var status: MirrorStatus = .off
    /// Nome da câmera em uso quando não é a do Mac (o iPhone ou uma webcam).
    private(set) var cameraName: String?
    /// A câmera do Mac está indisponível porque a tampa do MacBook está fechada.
    private(set) var lidClosed = false
    @ObservationIgnored var onActiveChange: () -> Void = {}

    @ObservationIgnored let session = AVCaptureSession()
    /// `startRunning`/`stopRunning` bloqueiam: rodam numa fila própria, em ordem.
    @ObservationIgnored private let queue = DispatchQueue(label: "marquise.camera")
    /// Câmera ligada à sessão (só lida e escrita na `queue`).
    @ObservationIgnored private var currentDeviceID: String?
    /// A pessoa já aceitou usar o iPhone enquanto o app está aberto: não pergunta de novo.
    @ObservationIgnored private var iPhoneAccepted = false
    @ObservationIgnored private var connectObserver: NSObjectProtocol?

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { return }
        isActive = true
        onActiveChange()
        guard Self.cameraEnabled else { return }
        status = .starting
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            chooseCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isActive else { return }
                    if granted { self.chooseCamera() } else { self.status = .denied }
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
        cameraName = nil
        if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        connectObserver = nil
        onActiveChange()
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    /// Para as imagens de conferência (`--snapshot`).
    func showDemo(_ status: MirrorStatus, camera: String?, lidClosed: Bool) {
        start()
        self.status = status
        cameraName = camera
        self.lidClosed = lidClosed
    }

    /// Resposta "Usar o iPhone" à pergunta do espelho.
    func useIPhone() {
        guard isActive, let iPhone = Self.continuityCamera() else {
            chooseCamera()
            return
        }
        iPhoneAccepted = true
        status = .starting
        run(with: iPhone)
    }

    /// A câmera do Mac (a que fica no notch) vem primeiro. Sem ela (MacBook fechado ou Mac sem
    /// câmera), oferece o iPhone pela Câmera de Continuidade; sem iPhone, usa outra webcam.
    private func chooseCamera() {
        guard isActive else { return }
        lidClosed = Self.isLidClosed
        // Com a tampa fechada o macOS ainda lista a câmera do MacBook, mas ela não entrega imagem.
        if !lidClosed,
           let builtIn = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) {
            run(with: builtIn)
            return
        }
        if let iPhone = Self.continuityCamera() {
            if iPhoneAccepted {
                run(with: iPhone)
            } else {
                cameraName = iPhone.localizedName
                status = .offerIPhone
            }
            return
        }
        if let other = Self.otherCamera() {
            run(with: other)
            return
        }
        status = .noCamera
        watchForCameras()
    }

    /// O iPhone pode aparecer depois que o espelho abriu (ao ser aproximado ou desbloqueado).
    private func watchForCameras() {
        guard connectObserver == nil else { return }
        connectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive, self.status == .noCamera else { return }
            self.chooseCamera()
        }
    }

    private func run(with device: AVCaptureDevice) {
        cameraName = device.deviceType == .builtInWideAngleCamera ? nil : device.localizedName
        queue.async { [weak self] in
            guard let self else { return }
            let ready = self.configure(device)
            if ready { self.session.startRunning() }
            DispatchQueue.main.async {
                // Fechado enquanto a câmera ligava: o stop() já está na fila, depois deste bloco.
                guard self.isActive else { return }
                self.status = ready ? .live : .noCamera
            }
        }
    }

    /// Liga a câmera escolhida à sessão, trocando a anterior se for outra (chame na `queue`).
    private func configure(_ device: AVCaptureDevice) -> Bool {
        if currentDeviceID == device.uniqueID { return true }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.sessionPreset = .high
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            currentDeviceID = nil
            return false
        }
        session.addInput(input)
        session.commitConfiguration()
        currentDeviceID = device.uniqueID
        return true
    }

    private static func continuityCamera() -> AVCaptureDevice? {
        // Dependendo de como o iPhone se conecta, ele aparece como "Continuidade" ou como câmera externa.
        cameras([.continuityCamera, .external]).first { $0.isContinuityCamera }
    }

    /// Webcam USB ou de monitor, se houver.
    private static func otherCamera() -> AVCaptureDevice? {
        cameras([.external]).first { !$0.isContinuityCamera }
    }

    private static func cameras(_ types: [AVCaptureDevice.DeviceType]) -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
    }

    private static var isLidClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (state?.takeRetainedValue() as? Bool) ?? false
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
                    // Com o iPhone ou outra webcam, o nome dela aparece ao lado.
                    Text(mirror.status == .live ? mirror.cameraName.map { L(.cameraMirror) + " · " + $0 } ?? L(.cameraMirror)
                                                : L(.cameraMirror))
                        .truncationMode(.middle)
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
                } else if mirror.status == .off {
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
                    .buttonStyle(PillButtonStyle(prominent: true))
            }
            .foregroundStyle(.white.opacity(0.8))
        case .noCamera:
            VStack(spacing: 10) {
                Image(systemName: model.mirror.lidClosed ? "iphone" : "video.slash").font(.system(size: 22))
                Text(model.mirror.lidClosed ? L(.lidClosedNoCamera) : L(.noCamera))
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .foregroundStyle(.white.opacity(0.7))
        case .offerIPhone:
            let mirror = model.mirror
            VStack(spacing: 12) {
                Image(systemName: "iphone.gen3").font(.system(size: 26))
                Text(mirror.lidClosed ? L(.lidClosedUseIPhone) : L(.noMacCameraUseIPhone))
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                HStack(spacing: 10) {
                    Button(L(.notNow)) { mirror.stop() }
                        .buttonStyle(PillButtonStyle(prominent: false))
                    Button(L(.useIPhone)) { mirror.useIPhone() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
            }
            .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// Botão em cápsula no estilo da ilha: branco (principal) ou translúcido.
struct PillButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.14)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
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
