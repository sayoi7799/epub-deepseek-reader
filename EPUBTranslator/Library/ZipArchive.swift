import Foundation

enum ZipError: Error, LocalizedError {
    case notAZipFile
    case corrupted(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notAZipFile:
            return "这不是一个有效的 ZIP / EPUB 文件"
        case .corrupted(let detail):
            return "文件结构损坏：\(detail)"
        case .unsupported(let detail):
            return "暂不支持这种文件：\(detail)"
        }
    }
}

/// 只读的 ZIP 解析器：读取中央目录，按需解压单个条目。
struct ZipArchive {
    struct Entry {
        let path: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let bytes: [UInt8]
    private(set) var entries: [Entry] = []

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        self.bytes = [UInt8](data)
        try readCentralDirectory()
    }

    init(data: Data) throws {
        self.bytes = [UInt8](data)
        try readCentralDirectory()
    }

    // MARK: - 解压

    func data(for entry: Entry) throws -> Data {
        let header = entry.localHeaderOffset
        guard try u32(header) == 0x04034B50 else {
            throw ZipError.corrupted("本地文件头签名错误：\(entry.path)")
        }
        let nameLength = try u16(header + 26)
        let extraLength = try u16(header + 28)
        let start = header + 30 + nameLength + extraLength
        guard start >= 0, start + entry.compressedSize <= bytes.count else {
            throw ZipError.corrupted("条目数据越界：\(entry.path)")
        }
        let payload = Array(bytes[start..<(start + entry.compressedSize)])
        switch entry.compressionMethod {
        case 0:
            return Data(payload)
        case 8:
            let plain = try Inflate.decompress(payload, expectedSize: entry.uncompressedSize)
            return Data(plain)
        default:
            throw ZipError.unsupported("未知的压缩方式 \(entry.compressionMethod)")
        }
    }

    func string(for entry: Entry) -> String? {
        guard let data = try? data(for: entry) else { return nil }
        return String.decodingText(from: data)
    }

    /// 把压缩包里所有文件解压到指定目录，返回写出的相对路径。
    @discardableResult
    func extract(to destination: URL) throws -> [String] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        var written: [String] = []
        for entry in entries {
            guard let path = ZipArchive.sanitized(path: entry.path) else { continue }
            if path.hasPrefix("__MACOSX/") { continue }
            let target = destination.appendingPathComponent(path)
            if path.hasSuffix("/") {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try data(for: entry)
            try data.write(to: target, options: [.atomic])
            written.append(path)
        }
        return written
    }

    static func sanitized(path: String) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let isDirectory = normalized.hasSuffix("/")
        let components = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." && $0 != ".." }
        guard !components.isEmpty else { return nil }
        let joined = components.joined(separator: "/")
        return isDirectory ? joined + "/" : joined
    }

    // MARK: - 中央目录

    private mutating func readCentralDirectory() throws {
        let eocd = try findEndOfCentralDirectory()
        var entryCount = try u16(eocd + 10)
        var directoryOffset = try u32(eocd + 16)

        if entryCount == 0xFFFF || directoryOffset == 0xFFFFFFFF {
            if let zip64 = try? zip64EndOfCentralDirectory(eocd: eocd) {
                entryCount = zip64.entryCount
                directoryOffset = zip64.directoryOffset
            }
        }

        var cursor = directoryOffset
        var result: [Entry] = []
        for _ in 0..<entryCount {
            guard try u32(cursor) == 0x02014B50 else {
                throw ZipError.corrupted("中央目录记录签名错误")
            }
            let flags = try u16(cursor + 8)
            let method = try u16(cursor + 10)
            var compressedSize = try u32(cursor + 20)
            var uncompressedSize = try u32(cursor + 24)
            let nameLength = try u16(cursor + 28)
            let extraLength = try u16(cursor + 30)
            let commentLength = try u16(cursor + 32)
            var localHeaderOffset = try u32(cursor + 42)

            let recordLength = 46 + nameLength + extraLength + commentLength
            guard cursor + recordLength <= bytes.count else {
                throw ZipError.corrupted("中央目录记录越界")
            }
            let nameBytes = Array(bytes[(cursor + 46)..<(cursor + 46 + nameLength)])
            let name = String(decoding: nameBytes, as: UTF8.self)

            if compressedSize == 0xFFFFFFFF || uncompressedSize == 0xFFFFFFFF || localHeaderOffset == 0xFFFFFFFF {
                let extraStart = cursor + 46 + nameLength
                let extra = Array(bytes[extraStart..<(extraStart + extraLength)])
                let zip64 = try zip64ExtraValues(
                    extra: extra,
                    wantsUncompressedSize: uncompressedSize == 0xFFFFFFFF,
                    wantsCompressedSize: compressedSize == 0xFFFFFFFF,
                    wantsOffset: localHeaderOffset == 0xFFFFFFFF
                )
                if let value = zip64.uncompressedSize { uncompressedSize = value }
                if let value = zip64.compressedSize { compressedSize = value }
                if let value = zip64.localHeaderOffset { localHeaderOffset = value }
            }

            if flags & 0x0001 != 0 {
                throw ZipError.unsupported("该压缩包带有密码保护")
            }

            result.append(
                Entry(
                    path: name,
                    compressionMethod: UInt16(clamping: method),
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )
            cursor += recordLength
        }
        entries = result
    }

    private func findEndOfCentralDirectory() throws -> Int {
        let minimumRecordSize = 22
        guard bytes.count >= minimumRecordSize else { throw ZipError.notAZipFile }
        let lowest = max(0, bytes.count - minimumRecordSize - 65535)
        var offset = bytes.count - minimumRecordSize
        while offset >= lowest {
            if bytes[offset] == 0x50, bytes[offset + 1] == 0x4B, bytes[offset + 2] == 0x05, bytes[offset + 3] == 0x06 {
                return offset
            }
            offset -= 1
        }
        throw ZipError.notAZipFile
    }

    private func zip64EndOfCentralDirectory(eocd: Int) throws -> (entryCount: Int, directoryOffset: Int) {
        let locator = eocd - 20
        guard locator >= 0, try u32(locator) == 0x07064B50 else {
            throw ZipError.corrupted("缺少 ZIP64 定位记录")
        }
        let recordOffset = try u64(locator + 8)
        guard try u32(recordOffset) == 0x06064B50 else {
            throw ZipError.corrupted("ZIP64 结尾记录签名错误")
        }
        let entryCount = try u64(recordOffset + 32)
        let directoryOffset = try u64(recordOffset + 48)
        return (entryCount, directoryOffset)
    }

    private func zip64ExtraValues(
        extra: [UInt8],
        wantsUncompressedSize: Bool,
        wantsCompressedSize: Bool,
        wantsOffset: Bool
    ) throws -> (uncompressedSize: Int?, compressedSize: Int?, localHeaderOffset: Int?) {
        var cursor = 0
        while cursor + 4 <= extra.count {
            let fieldID = Int(extra[cursor]) | (Int(extra[cursor + 1]) << 8)
            let fieldSize = Int(extra[cursor + 2]) | (Int(extra[cursor + 3]) << 8)
            let payloadStart = cursor + 4
            guard payloadStart + fieldSize <= extra.count else { break }
            if fieldID == 0x0001 {
                var payload = payloadStart
                var uncompressedSize: Int?
                var compressedSize: Int?
                var localHeaderOffset: Int?
                if wantsUncompressedSize {
                    uncompressedSize = try u64(payload)
                    payload += 8
                }
                if wantsCompressedSize {
                    compressedSize = try u64(payload)
                    payload += 8
                }
                if wantsOffset {
                    localHeaderOffset = try u64(payload)
                    payload += 8
                }
                return (uncompressedSize, compressedSize, localHeaderOffset)
            }
            cursor = payloadStart + fieldSize
        }
        throw ZipError.corrupted("缺少 ZIP64 扩展信息")
    }

    // MARK: - 小工具

    private func u16(_ offset: Int) throws -> Int {
        guard offset >= 0, offset + 2 <= bytes.count else {
            throw ZipError.corrupted("读取越界（16 位）")
        }
        return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
    }

    private func u32(_ offset: Int) throws -> Int {
        guard offset >= 0, offset + 4 <= bytes.count else {
            throw ZipError.corrupted("读取越界（32 位）")
        }
        return Int(bytes[offset])
            | (Int(bytes[offset + 1]) << 8)
            | (Int(bytes[offset + 2]) << 16)
            | (Int(bytes[offset + 3]) << 24)
    }

    private func u64(_ offset: Int) throws -> Int {
        guard offset >= 0, offset + 8 <= bytes.count else {
            throw ZipError.corrupted("读取越界（64 位）")
        }
        var value = 0
        for index in (0..<8).reversed() {
            value = (value << 8) | Int(bytes[offset + index])
        }
        return value
    }
}

extension String {
    /// 依次尝试常见编码，尽力把章节内容读出来（部分 EPUB 不是 UTF-8）。
    static func decodingText(from data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .utf16, .isoLatin1, .windowsCP1252, .shiftJIS, .japaneseEUC]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return nil
    }
}
