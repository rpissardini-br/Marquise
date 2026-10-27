import Foundation
import IOKit

/// Conversa com um monitor externo pelo próprio cabo (DDC/CI), em Macs com Apple Silicon.
/// É assim que dá para mudar o volume dos alto-falantes do monitor, que o macOS não controla
/// quando o som sai por DisplayPort ou HDMI.
///
/// Usa funções do IOKit que a Apple não documenta (as mesmas do MonitorControl). Elas são
/// carregadas na hora: em Macs onde não existem (Intel), o recurso só fica indisponível.
final class DDCDisplay {
    enum Code: UInt8 {
        case volume = 0x62
    }

    /// Toda conversa com monitores passa por esta fila, uma de cada vez: o DDC é lento
    /// e os monitores ignoram pedidos sobrepostos.
    static let queue = DispatchQueue(label: "marquise.ddc")

    private typealias CreateFunction = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias I2CFunction = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private static let createService = dlsym(iokit, "IOAVServiceCreateWithService")
        .map { unsafeBitCast($0, to: CreateFunction.self) }
    private static let readI2C = dlsym(iokit, "IOAVServiceReadI2C").map { unsafeBitCast($0, to: I2CFunction.self) }
    private static let writeI2C = dlsym(iokit, "IOAVServiceWriteI2C").map { unsafeBitCast($0, to: I2CFunction.self) }

    /// Endereços do padrão DDC/CI: o monitor fica em 0x37 e o Mac fala como 0x51.
    private static let chip: UInt32 = 0x37
    private static let host: UInt8 = 0x51
    private static let replyHost: UInt8 = 0x6E

    private let service: CFTypeRef

    private init(service: CFTypeRef) { self.service = service }

    /// Monitores externos conectados (chame na `queue`).
    static func external() -> [DDCDisplay] {
        guard let createService else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator)
            == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var displays: [DDCDisplay] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External", let service = createService(kCFAllocatorDefault, entry)?.takeRetainedValue()
            else { continue }
            displays.append(DDCDisplay(service: service))
        }
        return displays
    }

    /// Valor atual e máximo de um controle, ou nil se o monitor não respondeu (chame na `queue`).
    func read(_ code: Code) -> (value: Int, max: Int)? {
        guard let readI2C = Self.readI2C, let writeI2C = Self.writeI2C else { return nil }
        var request: [UInt8] = [0x82, 0x01, code.rawValue]
        request.append(Self.checksum(request))
        for _ in 0..<4 {
            var reply = [UInt8](repeating: 0, count: 12)
            let sent = request.withUnsafeMutableBytes {
                writeI2C(service, Self.chip, UInt32(Self.host), $0.baseAddress!, UInt32($0.count))
            }
            usleep(40_000)
            let received = reply.withUnsafeMutableBytes {
                readI2C(service, Self.chip, UInt32(Self.host), $0.baseAddress!, UInt32($0.count))
            }
            // Resposta: origem, tamanho, 0x02 (resposta de leitura), resultado, código, tipo, máx (2), atual (2).
            if sent == kIOReturnSuccess, received == kIOReturnSuccess,
               reply[2] == 0x02, reply[4] == code.rawValue {
                guard reply[3] == 0 else { return nil }  // o monitor não tem esse controle
                let max = Int(reply[6]) << 8 | Int(reply[7])
                let value = Int(reply[8]) << 8 | Int(reply[9])
                return max > 0 ? (value, max) : nil
            }
            usleep(40_000)
        }
        return nil
    }

    /// Muda um controle; devolve false se o monitor não aceitou (chame na `queue`).
    @discardableResult
    func write(_ code: Code, value: Int) -> Bool {
        guard let writeI2C = Self.writeI2C else { return false }
        let value = UInt16(clamping: max(0, value))
        var request: [UInt8] = [0x84, 0x03, code.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)]
        request.append(Self.checksum(request))
        for _ in 0..<2 {
            let sent = request.withUnsafeMutableBytes {
                writeI2C(service, Self.chip, UInt32(Self.host), $0.baseAddress!, UInt32($0.count))
            }
            if sent == kIOReturnSuccess { return true }
            usleep(20_000)
        }
        return false
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(replyHost ^ host, ^)
    }
}
