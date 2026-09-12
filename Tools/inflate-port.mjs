// 该文件是 EPUBTranslator/Library/Inflate.swift 的等价 JS 移植，
// 仅用于在没有 Xcode 的机器上验证解压算法本身是否正确。
import zlib from "node:zlib";

const CODE_LENGTH_ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

const LENGTH_BASE_AND_EXTRA = [
  [3, 0], [4, 0], [5, 0], [6, 0], [7, 0], [8, 0], [9, 0], [10, 0],
  [11, 1], [13, 1], [15, 1], [17, 1],
  [19, 2], [23, 2], [27, 2], [31, 2],
  [35, 3], [43, 3], [51, 3], [59, 3],
  [67, 4], [83, 4], [99, 4], [115, 4],
  [131, 5], [163, 5], [195, 5], [227, 5],
  [258, 0],
];

const DISTANCE_BASE_AND_EXTRA = [
  [1, 0], [2, 0], [3, 0], [4, 0],
  [5, 1], [7, 1],
  [9, 2], [13, 2],
  [17, 3], [25, 3],
  [33, 4], [49, 4],
  [65, 5], [97, 5],
  [129, 6], [193, 6],
  [257, 7], [385, 7],
  [513, 8], [769, 8],
  [1025, 9], [1537, 9],
  [2049, 10], [3073, 10],
  [4097, 11], [6145, 11],
  [8193, 12], [12289, 12],
  [16385, 13], [24577, 13],
];

function buildTable(lengths) {
  const counts = new Array(16).fill(0);
  for (const length of lengths) {
    if (length > 0) {
      if (length >= 16) throw new Error("invalid huffman code");
      counts[length] += 1;
    }
  }
  if (counts.every((value) => value === 0)) {
    return { counts, symbols: [] };
  }
  let left = 1;
  for (let length = 1; length <= 15; length += 1) {
    left <<= 1;
    left -= counts[length];
    if (left < 0) throw new Error("invalid huffman code");
  }
  const offsets = new Array(16).fill(0);
  let total = 0;
  for (let length = 1; length <= 15; length += 1) {
    offsets[length] = total;
    total += counts[length];
  }
  const symbols = new Array(total).fill(0);
  lengths.forEach((length, symbol) => {
    if (length > 0) {
      symbols[offsets[length]] = symbol;
      offsets[length] += 1;
    }
  });
  return { counts, symbols };
}

const FIXED_LENGTH_TABLE = (() => {
  const lengths = new Array(288).fill(0);
  for (let s = 0; s <= 143; s += 1) lengths[s] = 8;
  for (let s = 144; s <= 255; s += 1) lengths[s] = 9;
  for (let s = 256; s <= 279; s += 1) lengths[s] = 7;
  for (let s = 280; s <= 287; s += 1) lengths[s] = 8;
  return buildTable(lengths);
})();

const FIXED_DISTANCE_TABLE = buildTable(new Array(30).fill(5));

class Inflate {
  constructor(input, expectedSize) {
    this.input = input;
    this.cursor = 0;
    this.bitBuffer = 0;
    this.bitCount = 0;
    this.output = [];
    this.expectedSize = expectedSize || 0;
  }

  static decompress(data, expectedSize = 0) {
    const decoder = new Inflate(data, expectedSize);
    decoder.run();
    if (expectedSize > 0 && decoder.output.length !== expectedSize) {
      throw new Error(`length mismatch: expected ${expectedSize}, got ${decoder.output.length}`);
    }
    return Buffer.from(decoder.output);
  }

  run() {
    if (this.input.length === 0) throw new Error("empty input");
    let isFinalBlock = false;
    do {
      isFinalBlock = this.readBits(1) === 1;
      const blockType = this.readBits(2);
      if (blockType === 0) {
        this.readStoredBlock();
      } else if (blockType === 1) {
        this.readCompressedBlock(FIXED_LENGTH_TABLE, FIXED_DISTANCE_TABLE);
      } else if (blockType === 2) {
        const tables = this.readDynamicTables();
        this.readCompressedBlock(tables.length, tables.distance);
      } else {
        throw new Error(`unknown block type ${blockType}`);
      }
    } while (!isFinalBlock);
  }

  readStoredBlock() {
    this.alignToByte();
    const length = this.readBits(16);
    const inverseLength = this.readBits(16);
    if (length !== (~inverseLength & 0xffff)) throw new Error("invalid stored block");
    if (this.cursor + length > this.input.length) throw new Error("truncated input");
    for (let i = 0; i < length; i += 1) {
      this.output.push(this.input[this.cursor + i]);
    }
    this.cursor += length;
  }

  readCompressedBlock(lengthTable, distanceTable) {
    for (;;) {
      const symbol = this.decodeSymbol(lengthTable);
      if (symbol < 256) {
        this.output.push(symbol);
        continue;
      }
      if (symbol === 256) return;
      const lengthIndex = symbol - 257;
      if (lengthIndex < 0 || lengthIndex >= LENGTH_BASE_AND_EXTRA.length) throw new Error("invalid huffman code");
      const [lengthBase, lengthExtra] = LENGTH_BASE_AND_EXTRA[lengthIndex];
      const length = lengthBase + this.readBits(lengthExtra);

      const distanceSymbol = this.decodeSymbol(distanceTable);
      if (distanceSymbol < 0 || distanceSymbol >= DISTANCE_BASE_AND_EXTRA.length) throw new Error("invalid huffman code");
      const [distanceBase, distanceExtra] = DISTANCE_BASE_AND_EXTRA[distanceSymbol];
      const distance = distanceBase + this.readBits(distanceExtra);
      if (distance <= 0 || distance > this.output.length) throw new Error(`invalid distance ${distance}`);

      let source = this.output.length - distance;
      for (let i = 0; i < length; i += 1) {
        this.output.push(this.output[source]);
        source += 1;
      }
    }
  }

  readDynamicTables() {
    const lengthCount = this.readBits(5) + 257;
    const distanceCount = this.readBits(5) + 1;
    const codeLengthCount = this.readBits(4) + 4;

    const codeLengthLengths = new Array(19).fill(0);
    for (let index = 0; index < codeLengthCount; index += 1) {
      codeLengthLengths[CODE_LENGTH_ORDER[index]] = this.readBits(3);
    }
    const codeLengthTable = buildTable(codeLengthLengths);

    const total = lengthCount + distanceCount;
    const lengths = new Array(total).fill(0);
    let index = 0;
    while (index < total) {
      const symbol = this.decodeSymbol(codeLengthTable);
      if (symbol < 16) {
        lengths[index] = symbol;
        index += 1;
      } else if (symbol === 16) {
        if (index === 0) throw new Error("invalid huffman code");
        const repeatCount = 3 + this.readBits(2);
        const previous = lengths[index - 1];
        for (let i = 0; i < repeatCount; i += 1) {
          if (index >= total) throw new Error("invalid huffman code");
          lengths[index] = previous;
          index += 1;
        }
      } else if (symbol === 17) {
        index += 3 + this.readBits(3);
      } else if (symbol === 18) {
        index += 11 + this.readBits(7);
      } else {
        throw new Error("invalid huffman code");
      }
      if (index > total) throw new Error("invalid huffman code");
    }

    return {
      length: buildTable(lengths.slice(0, lengthCount)),
      distance: buildTable(lengths.slice(lengthCount, total)),
    };
  }

  alignToByte() {
    this.bitBuffer = 0;
    this.bitCount = 0;
  }

  readBit() {
    if (this.bitCount === 0) {
      if (this.cursor >= this.input.length) throw new Error("truncated input");
      this.bitBuffer = this.input[this.cursor];
      this.cursor += 1;
      this.bitCount = 8;
    }
    const bit = this.bitBuffer & 1;
    this.bitBuffer >>= 1;
    this.bitCount -= 1;
    return bit;
  }

  readBits(count) {
    if (count <= 0) return 0;
    let value = 0;
    for (let shift = 0; shift < count; shift += 1) {
      value |= this.readBit() << shift;
    }
    return value;
  }

  decodeSymbol(table) {
    let code = 0;
    let first = 0;
    let index = 0;
    for (let length = 1; length <= 15; length += 1) {
      code |= this.readBit();
      const count = table.counts[length];
      if (code < first + count) {
        const symbolIndex = index + (code - first);
        if (symbolIndex < 0 || symbolIndex >= table.symbols.length) throw new Error("invalid huffman code");
        return table.symbols[symbolIndex];
      }
      index += count;
      first = (first + count) << 1;
      code <<= 1;
    }
    throw new Error("invalid huffman code");
  }
}

export { Inflate, buildTable };

export function rawDeflateOfZlibStream(buffer) {
  // 去掉 zlib 头（2 字节）和 adler32 尾（4 字节），得到 raw DEFLATE。
  return buffer.subarray(2, buffer.length - 4);
}

export function zlibStreamOfRawDeflate(raw) {
  return zlib.inflateSync(raw, { finishFlush: zlib.constants.Z_SYNC_FLUSH });
}
