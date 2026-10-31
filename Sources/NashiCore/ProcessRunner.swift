import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let output: Data
    public let errorOutput: Data
    public var text: String { String(decoding: output, as: UTF8.self) }
}

public enum ProcessRunner {
    /// Each tool runs in its own process group, so Cancel, app termination and
    /// a normal exit also stop the helpers it started (LibreOffice, ffmpeg under
    /// yt-dlp). Those helpers inherit the output pipes; waiting for the pipes to
    /// close is bounded. Arguments are argv entries; no shell is involved.
    @discardableResult
    public static func run(_ executable: URL, _ arguments: [String], directory: URL? = nil, token: CancellationToken = .init(), environment: [String: String] = [:], onOutput: (@Sendable (Data) -> Void)? = nil) throws -> ProcessResult {
        try token.check()
        // Conversion inputs stay local even if a media container references an
        // external playlist segment. Local pipes/data/encrypted files still work.
        let arguments = ["ffmpeg","ffprobe"].contains(executable.lastPathComponent) && !arguments.contains("-protocol_whitelist") ? ["-protocol_whitelist","file,pipe,crypto,data"]+arguments:arguments
        let variables = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let output = Pipe(), errors = Pipe()
        let pid = try spawn(executable, arguments, directory: directory, environment: variables, output: output, errors: errors)
        running.insert(pid)
        defer { running.remove(pid) }
        // Drain both streams concurrently: codec diagnostics can exceed a pipe buffer.
        let group = DispatchGroup()
        let captured = Capture(keepsTail: onOutput != nil)
        group.enter()
        DispatchQueue.global().async {
            defer { try? output.fileHandleForReading.close(); group.leave() }
            // availableData returns as soon as bytes arrive; read(upToCount:) can
            // wait for a full buffer and leave a short progress stream stuck at 0%.
            while true {
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else { break }
                captured.appendOutput(chunk)
                onOutput?(chunk)
            }
        }
        group.enter()
        DispatchQueue.global().async {
            defer { try? errors.fileHandleForReading.close(); group.leave() }
            while true {
                let chunk = errors.fileHandleForReading.availableData
                guard !chunk.isEmpty else { break }
                captured.appendErrors(chunk)
            }
        }
        var status: Int32 = 0, stoppingAt: Date?
        while true {
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid { break }
            if waited < 0 {
                if errno == EINTR { continue }
                status = -1; break
            }
            if token.isCancelled || running.isStopping(pid) {
                if stoppingAt == nil { stoppingAt = Date(); kill(-pid, SIGTERM) }
                else if Date().timeIntervalSince(stoppingAt!) > stopGrace { kill(-pid, SIGKILL) }
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        // Helpers left in the group must not outlive the tool or hold its pipes open.
        kill(-pid, SIGTERM)
        if group.wait(timeout: .now() + stopGrace) == .timedOut {
            kill(-pid, SIGKILL)
            // A helper that left the group can still hold a pipe; stop waiting for it.
            _ = group.wait(timeout: .now() + stopGrace)
        }
        try token.check()
        let result = captured.result
        let signalled = status & 0x7f != 0
        let code = status < 0 ? status : signalled ? status & 0x7f : (status >> 8) & 0xff
        guard status == 0 else {
            let diagnostic = String(decoding: result.errorOutput.suffix(6000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw NashiError.failed(diagnostic.isEmpty ? "\(executable.lastPathComponent) exited with code \(code)." : diagnostic)
        }
        return result
    }

    /// Time a process group gets to exit after SIGTERM before SIGKILL.
    static let stopGrace: TimeInterval = 2

    private static func spawn(_ executable: URL, _ arguments: [String], directory: URL?, environment: [String: String], output: Pipe, errors: Pipe) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errors.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        if let directory { posix_spawn_file_actions_addchdir_np(&actions, directory.path) }
        // Only the three standard streams reach the child: an inherited pipe of a
        // concurrent run would otherwise stay open (no EOF) until this tool ends.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in argv { free(pointer) }; for pointer in envp { free(pointer) } }
        var pid: pid_t = 0
        let status = argv.withUnsafeBufferPointer { args in envp.withUnsafeBufferPointer { env in
            posix_spawn(&pid, executable.path, &actions, &attributes, UnsafeMutablePointer(mutating: args.baseAddress!), UnsafeMutablePointer(mutating: env.baseAddress!))
        } }
        try? output.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
        guard status == 0 else {
            try? output.fileHandleForReading.close(); try? errors.fileHandleForReading.close()
            throw NashiError.failed("\(executable.lastPathComponent) could not start: \(String(cString: strerror(status))).")
        }
        return pid
    }

    private final class Capture: @unchecked Sendable {
        private let lock = NSLock(), keepsTail: Bool
        private var output = Data(), errors = Data()
        init(keepsTail: Bool) { self.keepsTail = keepsTail }
        func appendOutput(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            output.append(data)
            if keepsTail && output.count > 2_000_000 { output.removeFirst(output.count - 2_000_000) }
        }
        func appendErrors(_ data: Data) { lock.lock(); errors.append(data); lock.unlock() }
        var result: ProcessResult { lock.lock(); defer { lock.unlock() }; return ProcessResult(output: output, errorOutput: errors) }
    }

    /// Stops every child still running, for app termination: a cancelled token is
    /// only observed by the polling thread, which does not outlive the app. Each
    /// process group gets SIGTERM, then SIGKILL; the wait is bounded.
    public static func terminateAll() {
        let groups = running.stopAll()
        guard !groups.isEmpty else { return }
        for pid in groups { kill(-pid, SIGTERM) }
        let deadline = Date().addingTimeInterval(stopGrace)
        while Date() < deadline, running.contains(any: groups) { Thread.sleep(forTimeInterval: 0.02) }
        for pid in groups where running.contains(any: [pid]) { kill(-pid, SIGKILL) }
    }
    private static let running = Running()
    private final class Running: @unchecked Sendable {
        private let lock = NSLock()
        private var groups: [pid_t: Bool] = [:]
        func insert(_ pid: pid_t) { lock.lock(); groups[pid] = false; lock.unlock() }
        func remove(_ pid: pid_t) { lock.lock(); groups[pid] = nil; lock.unlock() }
        func isStopping(_ pid: pid_t) -> Bool { lock.lock(); defer { lock.unlock() }; return groups[pid] == true }
        func contains(any pids: [pid_t]) -> Bool { lock.lock(); defer { lock.unlock() }; return pids.contains { groups[$0] != nil } }
        func stopAll() -> [pid_t] {
            lock.lock(); defer { lock.unlock() }
            for pid in groups.keys { groups[pid] = true }
            return Array(groups.keys)
        }
    }
}

public enum Dependencies {
    public static func executable(_ name: String) throws -> URL {
        let fm = FileManager.default
        let variable = "NASHI_" + name.uppercased()
        var paths: [String] = []
        if let override = ProcessInfo.processInfo.environment[variable] ?? ProcessInfo.processInfo.environment["TANGERINE_"+name.uppercased()] { paths.append(override) }
        if let resource = Bundle.main.resourceURL {
            paths.append(resource.appendingPathComponent("Tools/\(name)").path)
            if name == "exiftool" { paths.append(resource.appendingPathComponent("Tools/ExifTool/exiftool").path) }
            if name == "soffice" { paths.append(resource.appendingPathComponent("Tools/LibreOffice.app/Contents/MacOS/soffice").path) }
        }
        if let external=ExternalToolSetup.executable(name) { paths.append(external.path) }
        #if DEBUG
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        paths.append(root.appendingPathComponent("Tools/\(name)").path)
        if name == "exiftool" { paths.append(root.appendingPathComponent("Tools/ExifTool/exiftool").path) }
        if name == "soffice" { paths.append(root.appendingPathComponent("Tools/LibreOffice.app/Contents/MacOS/soffice").path) }
        #endif
        paths += ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        if name == "soffice" { paths.append("/Applications/LibreOffice.app/Contents/MacOS/soffice") }
        guard let found = paths.first(where: { path in
            // Search permission makes a directory "executable" too. In
            // particular, ExifTool and exiftool collide on the default macOS
            // filesystem; select the actual script inside that directory.
            let resolved=URL(fileURLWithPath:path).resolvingSymlinksInPath()
            let values=try? resolved.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
            return fm.isExecutableFile(atPath:resolved.path) && values?.isRegularFile == true && (values?.fileSize ?? 0)>0
        }) else { throw NashiError.missingDependency(name) }
        return URL(fileURLWithPath: found)
    }
}

public enum OutputFiles {
    /// Re-encoding an already optimized file must not increase its size or lose
    /// quality. Call only when output format and requested geometry are unchanged.
    static func retainSmallerOriginal(_ input:URL,output:URL,target:Int64?) throws {
        guard input.pathExtension.lowercased()==output.pathExtension.lowercased() else { return }
        let manager=FileManager.default
        let source=input.resolvingSymlinksInPath()
        let original=(try manager.attributesOfItem(atPath:source.path)[.size] as? NSNumber)?.int64Value ?? 0
        let encoded=(try manager.attributesOfItem(atPath:output.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard original>0,encoded>original,target == nil || original<=target! else { return }
        try manager.removeItem(at:output);try manager.copyItem(at:source,to:output)
    }
    public static func unique(for input: URL, extension ext: String, suffix: String = "", directory: URL? = nil) -> URL {
        let dir = directory ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent + suffix
        let cleanExt = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        var candidate = dir.appendingPathComponent(stem).appendingPathExtension(cleanExt)
        var index = 2
        // lstat-based: a dangling link still occupies its name. fileExists would
        // report it free, so moves fail and atomic writes replace the link.
        while (try? FileManager.default.attributesOfItem(atPath: candidate.path)) != nil {
            candidate = dir.appendingPathComponent("\(stem) \(index)").appendingPathExtension(cleanExt); index += 1
        }
        return candidate
    }
    /// Moves `source` into `directory` under its own name, or "Name 2", "Name 3"…
    /// when that is taken, and returns where it landed. An existing item is never
    /// replaced, even one another app creates after the name was chosen.
    public static func move(_ source:URL,into directory:URL) throws -> URL {
        try move(source,into:directory,willMove:nil)
    }
    static func move(_ source:URL,into directory:URL,willMove:((URL)->Void)?) throws -> URL {
        // attributesOfItem does not follow links, so a dangling link also takes a name.
        let taken={ (url:URL) in (try? FileManager.default.attributesOfItem(atPath:url.path)) != nil }
        var target=directory.appendingPathComponent(source.lastPathComponent),index=2
        func next() { target=directory.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent) \(index)").appendingPathExtension(source.pathExtension.lowercased());index+=1 }
        while true {
            while taken(target) { next() }
            willMove?(target)
            // moveItem checks the destination and then renames, so a file created
            // in between is replaced. RENAME_EXCL checks and renames in one step.
            let code=source.withUnsafeFileSystemRepresentation { from in
                target.withUnsafeFileSystemRepresentation { to in renamex_np(from!,to!,UInt32(RENAME_EXCL))==0 ? 0:errno }
            }
            if code==0 { return target }
            if code==EEXIST { next();continue }
            // Other volumes (EXDEV) and file systems without RENAME_EXCL (exFAT:
            // ENOTSUP) keep the previous behavior, which also reports other errors.
            try FileManager.default.moveItem(at:source,to:target)
            return target
        }
    }
    public static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nashi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    public static func validate(_ urls: [URL]) throws {
        guard !urls.isEmpty else { throw NashiError.failed("No output was produced.") }
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            guard values.isDirectory == true || (values.fileSize ?? 0) > 0 else { throw NashiError.failed("An empty output was produced: \(url.lastPathComponent)") }
        }
    }
}
