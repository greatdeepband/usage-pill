import Foundation

public protocol KeychainItemReading: Sendable {
    func read(service: String) throws -> Data
}

public enum KeychainReadError: Error, Equatable {
    case notFound          // security exit 44 (errSecItemNotFound)
    case toolFailed(Int32) // other non-zero exit
    case spawnFailed       // could not launch the tool
    case timedOut          // tool exceeded the watchdog window
}

/// Reads via Apple's `/usr/bin/security` rather than SecItemCopyMatching. The
/// security binary is admitted by the item's `apple-tool:` partition, so the
/// read is SILENT regardless of OUR signing identity / rebuild cdhash / the
/// owner's rotation — which is what stops the recurring keychain prompt.
///
/// Strictly READ-ONLY: `-w` only prints the secret; never writes the item, its
/// ACL, or partition list; never refreshes. The token is OUTPUT, never an argv
/// (invisible to `ps`); never `-g` (which would route it to stderr). No shell.
/// Buffer zeroing is best-effort only (the token lives on as a String).
public struct SecurityToolReader: KeychainItemReading {
    public static func defaultArguments(_ service: String) -> [String] {
        ["find-generic-password", "-s", service, "-w"]
    }
    private let toolPath: String
    private let timeout: TimeInterval
    private let killGrace: TimeInterval
    private let arguments: @Sendable (String) -> [String]

    public init(
        toolPath: String = "/usr/bin/security",
        timeout: TimeInterval = 5,
        killGrace: TimeInterval = 1,
        arguments: @escaping @Sendable (String) -> [String] = SecurityToolReader.defaultArguments
    ) {
        self.toolPath = toolPath; self.timeout = timeout
        self.killGrace = killGrace; self.arguments = arguments
    }

    public func read(service: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments(service)
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err; process.standardInput = nil

        do { try process.run() } catch { throw KeychainReadError.spawnFailed }
        let pid = process.processIdentifier

        // Bounded termination: SIGTERM at `timeout`, escalate to SIGKILL at
        // `timeout + killGrace` so a signal-ignoring child can NEVER hang us.
        // SIGKILL guarantees the pipe closes, so readDataToEndOfFile returns.
        let flag = TimedOutFlag()
        let term = DispatchWorkItem { if process.isRunning { flag.set(); process.terminate() } }
        let kill9 = DispatchWorkItem { if process.isRunning { kill(pid, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: term)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout + killGrace, execute: kill9)

        let raw = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()   // drained; NEVER logged
        process.waitUntilExit()
        term.cancel(); kill9.cancel()

        if flag.value { throw KeychainReadError.timedOut }
        let status = process.terminationStatus
        guard status == 0 else {
            throw status == 44 ? KeychainReadError.notFound : KeychainReadError.toolFailed(status)
        }
        var bytes = raw
        if bytes.last == 0x0A { bytes.removeLast() }   // `security -w` appends one newline
        return Self.decodeIfHex(bytes)                  // empty stays empty → parse → .unreadable (old behavior)
    }

    /// `security -w` hex-encodes the secret iff it contains any byte ≥ 0x80 or a
    /// newline. Decode an even-length all-hex run; otherwise return as-is. A real
    /// credential JSON always contains non-hex bytes (`{ " :`), so raw is never
    /// mistaken for hex.
    static func decodeIfHex(_ bytes: Data) -> Data {
        let isHex: (UInt8) -> Bool = { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) || (0x41...0x46).contains($0) }
        guard !bytes.isEmpty, bytes.count % 2 == 0, bytes.allSatisfy(isHex) else { return bytes }
        func nibble(_ b: UInt8) -> UInt8 { b <= 0x39 ? b - 0x30 : (b | 0x20) - 0x61 + 10 }
        var decoded = Data(capacity: bytes.count / 2)
        var i = bytes.startIndex
        while i < bytes.endIndex {
            decoded.append(nibble(bytes[i]) << 4 | nibble(bytes[bytes.index(after: i)]))
            i = bytes.index(i, offsetBy: 2)
        }
        return decoded
    }
}

/// Minimal lock-guarded flag for the watchdog→reader handoff (set off-thread).
final class TimedOutFlag: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    func set() { lock.lock(); v = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return v }
}
