import Foundation

/// 纯 Swift 实现的 DEFLATE（RFC 1951）解压器。
///
/// EPUB 本质上是一个 ZIP 文件，里面的章节内容是 DEFLATE 压缩的。
/// 为了让 App 不依赖任何第三方库，这里自己实现一个解压器，
/// 逻辑与 zlib 的 puff.c 一致（逐位解码哈夫曼码）。
enum InflateError: Error, LocalizedError {
    case emptyInput
    case truncatedInput
    case unknownBlockType(Int)
    case invalidHuffmanCode
    case invalidStoredBlock
    case invalidDistance(Int)
    case lengthMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "压缩数据为空"
        case .truncatedInput:
            return "压缩数据在读取过程中提前结束"
        case .unknownBlockType(let type):
            return "不支持的压缩块类型：\(type)"
        case .invalidHuffmanCode:
            return "压缩数据中的哈夫曼编码无效"
        case .invalidStoredBlock:
            return "压缩数据中的原始块校验失败"
        case .invalidDistance(let distance):
            return "压缩数据中的回溯距离无效：\(distance)"
        case .lengthMismatch(let expected, let actual):
            return "解压结果长度不符（期望 \(expected) 字节，实际 \(actual) 字节）"
        }
    }
}

struct Inflate {
    /// 哈夫曼表：counts[len] 表示长度为 len 的码字数量，symbols 按码字顺序排列的符号表。
    private struct HuffmanTable {
        var counts: [Int]
        var symbols: [Int]
    }

    private var input: [UInt8]
    private var cursor: Int = 0
    private var bitBuffer: UInt32 = 0
    private var bitCount: Int = 0
    private var output: [UInt8] = []

    private init(input: [UInt8], expectedSize: Int) {
        self.input = input
        if expectedSize > 0 {
            output.reserveCapacity(expectedSize)
        }
    }

    /// 解压一段 raw DEFLATE 数据。
    /// - Parameters:
    ///   - data: 不含 zlib 头尾的原始 DEFLATE 数据。
    ///   - expectedSize: 期望的输出长度，大于 0 时会做长度校验。
    static func decompress(_ data: [UInt8], expectedSize: Int = 0) throws -> [UInt8] {
        var decoder = Inflate(input: data, expectedSize: expectedSize)
        try decoder.run()
        if expectedSize > 0 && decoder.output.count != expectedSize {
            throw InflateError.lengthMismatch(expected: expectedSize, actual: decoder.output.count)
        }
        return decoder.output
    }

    static func decompress(_ data: Data, expectedSize: Int = 0) throws -> Data {
        Data(try decompress([UInt8](data), expectedSize: expectedSize))
    }

    // MARK: - 主循环

    private mutating func run() throws {
        guard !input.isEmpty else { throw InflateError.emptyInput }
        var isFinalBlock = false
        repeat {
            isFinalBlock = try readBits(1) == 1
            let blockType = try readBits(2)
            switch blockType {
            case 0:
                try readStoredBlock()
            case 1:
                try readCompressedBlock(lengthTable: Self.fixedLengthTable, distanceTable: Self.fixedDistanceTable)
            case 2:
                let tables = try readDynamicTables()
                try readCompressedBlock(lengthTable: tables.length, distanceTable: tables.distance)
            default:
                throw InflateError.unknownBlockType(blockType)
            }
        } while !isFinalBlock
    }

    private mutating func readStoredBlock() throws {
        alignToByte()
        let length = try readBits(16)
        let inverseLength = try readBits(16)
        guard length == (~inverseLength & 0xFFFF) else { throw InflateError.invalidStoredBlock }
        guard cursor + length <= input.count else { throw InflateError.truncatedInput }
        output.append(contentsOf: input[cursor..<(cursor + length)])
        cursor += length
    }

    private mutating func readCompressedBlock(lengthTable: HuffmanTable, distanceTable: HuffmanTable) throws {
        while true {
            let symbol = try decodeSymbol(lengthTable)
            if symbol < 256 {
                output.append(UInt8(symbol))
                continue
            }
            if symbol == 256 {
                return
            }
            let lengthIndex = symbol - 257
            guard lengthIndex >= 0 && lengthIndex < Self.lengthBaseAndExtra.count else {
                throw InflateError.invalidHuffmanCode
            }
            let lengthEntry = Self.lengthBaseAndExtra[lengthIndex]
            let length = lengthEntry.base + (try readBits(lengthEntry.extra))

            let distanceSymbol = try decodeSymbol(distanceTable)
            guard distanceSymbol >= 0 && distanceSymbol < Self.distanceBaseAndExtra.count else {
                throw InflateError.invalidHuffmanCode
            }
            let distanceEntry = Self.distanceBaseAndExtra[distanceSymbol]
            let distance = distanceEntry.base + (try readBits(distanceEntry.extra))
            guard distance > 0 && distance <= output.count else {
                throw InflateError.invalidDistance(distance)
            }

            var source = output.count - distance
            for _ in 0..<length {
                output.append(output[source])
                source += 1
            }
        }
    }

    private mutating func readDynamicTables() throws -> (length: HuffmanTable, distance: HuffmanTable) {
        let lengthCount = try readBits(5) + 257
        let distanceCount = try readBits(5) + 1
        let codeLengthCount = try readBits(4) + 4

        var codeLengthLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            codeLengthLengths[Self.codeLengthOrder[index]] = try readBits(3)
        }
        let codeLengthTable = try Self.buildTable(codeLengthLengths)

        let total = lengthCount + distanceCount
        var lengths = [Int](repeating: 0, count: total)
        var index = 0
        while index < total {
            let symbol = try decodeSymbol(codeLengthTable)
            switch symbol {
            case 0..<16:
                lengths[index] = symbol
                index += 1
            case 16:
                guard index > 0 else { throw InflateError.invalidHuffmanCode }
                let repeatCount = 3 + (try readBits(2))
                let previous = lengths[index - 1]
                for _ in 0..<repeatCount {
                    guard index < total else { throw InflateError.invalidHuffmanCode }
                    lengths[index] = previous
                    index += 1
                }
            case 17:
                let repeatCount = 3 + (try readBits(3))
                index += repeatCount
            case 18:
                let repeatCount = 11 + (try readBits(7))
                index += repeatCount
            default:
                throw InflateError.invalidHuffmanCode
            }
            guard index <= total else { throw InflateError.invalidHuffmanCode }
        }

        let lengthTable = try Self.buildTable(Array(lengths[0..<lengthCount]))
        let distanceTable = try Self.buildTable(Array(lengths[lengthCount..<total]))
        return (lengthTable, distanceTable)
    }

    // MARK: - 比特读取

    private mutating func alignToByte() {
        bitBuffer = 0
        bitCount = 0
    }

    private mutating func readBit() throws -> Int {
        if bitCount == 0 {
            guard cursor < input.count else { throw InflateError.truncatedInput }
            bitBuffer = UInt32(input[cursor])
            cursor += 1
            bitCount = 8
        }
        let bit = Int(bitBuffer & 1)
        bitBuffer >>= 1
        bitCount -= 1
        return bit
    }

    private mutating func readBits(_ count: Int) throws -> Int {
        guard count > 0 else { return 0 }
        var value = 0
        for shift in 0..<count {
            value |= (try readBit()) << shift
        }
        return value
    }

    // MARK: - 哈夫曼

    private mutating func decodeSymbol(_ table: HuffmanTable) throws -> Int {
        var code = 0
        var first = 0
        var index = 0
        for length in 1...15 {
            code |= try readBit()
            let count = table.counts[length]
            if code < first + count {
                let symbolIndex = index + (code - first)
                guard symbolIndex >= 0 && symbolIndex < table.symbols.count else {
                    throw InflateError.invalidHuffmanCode
                }
                return table.symbols[symbolIndex]
            }
            index += count
            first = (first + count) << 1
            code <<= 1
        }
        throw InflateError.invalidHuffmanCode
    }

    private static func buildTable(_ lengths: [Int]) throws -> HuffmanTable {
        var counts = [Int](repeating: 0, count: 16)
        for length in lengths where length > 0 {
            guard length < 16 else { throw InflateError.invalidHuffmanCode }
            counts[length] += 1
        }
        if counts.allSatisfy({ $0 == 0 }) {
            return HuffmanTable(counts: counts, symbols: [])
        }

        // 检验码字是否过长（over-subscribed）。
        var left = 1
        for length in 1...15 {
            left <<= 1
            left -= counts[length]
            if left < 0 { throw InflateError.invalidHuffmanCode }
        }

        var offsets = [Int](repeating: 0, count: 16)
        var total = 0
        for length in 1...15 {
            offsets[length] = total
            total += counts[length]
        }
        var symbols = [Int](repeating: 0, count: total)
        for (symbol, length) in lengths.enumerated() where length > 0 {
            symbols[offsets[length]] = symbol
            offsets[length] += 1
        }
        return HuffmanTable(counts: counts, symbols: symbols)
    }

    // MARK: - 常量表

    private static let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static let lengthBaseAndExtra: [(base: Int, extra: Int)] = [
        (3, 0), (4, 0), (5, 0), (6, 0), (7, 0), (8, 0), (9, 0), (10, 0),
        (11, 1), (13, 1), (15, 1), (17, 1),
        (19, 2), (23, 2), (27, 2), (31, 2),
        (35, 3), (43, 3), (51, 3), (59, 3),
        (67, 4), (83, 4), (99, 4), (115, 4),
        (131, 5), (163, 5), (195, 5), (227, 5),
        (258, 0)
    ]

    private static let distanceBaseAndExtra: [(base: Int, extra: Int)] = [
        (1, 0), (2, 0), (3, 0), (4, 0),
        (5, 1), (7, 1),
        (9, 2), (13, 2),
        (17, 3), (25, 3),
        (33, 4), (49, 4),
        (65, 5), (97, 5),
        (129, 6), (193, 6),
        (257, 7), (385, 7),
        (513, 8), (769, 8),
        (1025, 9), (1537, 9),
        (2049, 10), (3073, 10),
        (4097, 11), (6145, 11),
        (8193, 12), (12289, 12),
        (16385, 13), (24577, 13)
    ]

    private static let fixedLengthTable: HuffmanTable = {
        var lengths = [Int](repeating: 0, count: 288)
        for symbol in 0...143 { lengths[symbol] = 8 }
        for symbol in 144...255 { lengths[symbol] = 9 }
        for symbol in 256...279 { lengths[symbol] = 7 }
        for symbol in 280...287 { lengths[symbol] = 8 }
        return (try? buildTable(lengths)) ?? HuffmanTable(counts: [Int](repeating: 0, count: 16), symbols: [])
    }()

    private static let fixedDistanceTable: HuffmanTable = {
        let lengths = [Int](repeating: 5, count: 30)
        return (try? buildTable(lengths)) ?? HuffmanTable(counts: [Int](repeating: 0, count: 16), symbols: [])
    }()
}
