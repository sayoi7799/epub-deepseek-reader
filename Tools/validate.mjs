// 验证 Inflate + ZipArchive 的算法移植（对应 Swift 里的 Inflate.swift / ZipArchive.swift）。
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { Inflate } from "./inflate-port.mjs";
import { readZip, zipEntryData } from "./zip-port.mjs";

let failures = 0;

function check(name, condition, detail = "") {
  if (condition) {
    console.log(`  ok   ${name}`);
  } else {
    failures += 1;
    console.log(`  FAIL ${name} ${detail}`);
  }
}

function randomBytes(size) {
  const buffer = Buffer.alloc(size);
  for (let i = 0; i < size; i += 1) buffer[i] = Math.floor(Math.random() * 256);
  return buffer;
}

function sampleText(size) {
  const words = [
    "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "翻译", "章",
    "chapter", "said", "she", "quietly", "morning", "light", "window", "again",
  ];
  let text = "";
  while (text.length < size) {
    text += words[Math.floor(Math.random() * words.length)] + " ";
  }
  return Buffer.from(text.slice(0, size), "utf8");
}

console.log("1) Deflate 解压（各种压缩级别 / 策略 / 数据类型）");
const strategies = [
  ["default", zlib.constants.Z_DEFAULT_STRATEGY],
  ["filtered", zlib.constants.Z_FILTERED],
  ["huffmanOnly", zlib.constants.Z_HUFFMAN_ONLY],
  ["rle", zlib.constants.Z_RLE],
  ["fixed", zlib.constants.Z_FIXED],
];
const payloads = [
  ["empty", Buffer.alloc(0)],
  ["tiny", Buffer.from("hi")],
  ["text-1k", sampleText(1024)],
  ["text-64k", sampleText(64 * 1024)],
  ["random-8k", randomBytes(8 * 1024)],
  ["random-200k", randomBytes(200 * 1024)],
  ["repeat-128k", Buffer.alloc(128 * 1024, 0x41)],
];

for (const [payloadName, payload] of payloads) {
  for (let level = 0; level <= 9; level += 1) {
    for (const [strategyName, strategy] of strategies) {
      if (strategy !== zlib.constants.Z_DEFAULT_STRATEGY && level !== 6) continue;
      const raw = zlib.deflateRawSync(payload, { level, strategy });
      let actual;
      try {
        actual = Inflate.decompress([...raw], payload.length);
      } catch (error) {
        check(`${payloadName} level=${level} ${strategyName}`, false, `threw ${error.message}`);
        continue;
      }
      check(
        `${payloadName} level=${level} ${strategyName}`,
        Buffer.compare(actual, payload) === 0,
        `expected ${payload.length} bytes, got ${actual.length}`,
      );
    }
  }
}

console.log("2) zlib 流（去掉头尾后）解压");
for (const [payloadName, payload] of payloads) {
  const wrapped = zlib.deflateSync(payload, { level: 9 });
  const raw = wrapped.subarray(2, wrapped.length - 4);
  let actual;
  try {
    actual = Inflate.decompress([...raw]);
  } catch (error) {
    check(`zlib-stripped ${payloadName}`, false, `threw ${error.message}`);
    continue;
  }
  check(`zlib-stripped ${payloadName}`, Buffer.compare(actual, payload) === 0);
}

console.log("3) 手工构造的 ZIP（stored + deflate 混合）");
function buildZip(entries) {
  const localChunks = [];
  const centralChunks = [];
  let offset = 0;
  for (const entry of entries) {
    const nameBytes = Buffer.from(entry.name, "utf8");
    const raw = entry.compress
      ? zlib.deflateRawSync(entry.data, { level: 9 })
      : entry.data;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt16LE(entry.compress ? 8 : 0, 8);
    local.writeUInt32LE(raw.length, 18);
    local.writeUInt32LE(entry.data.length, 22);
    local.writeUInt16LE(nameBytes.length, 26);
    localChunks.push(local, nameBytes, raw);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(entry.compress ? 8 : 0, 10);
    central.writeUInt32LE(raw.length, 20);
    central.writeUInt32LE(entry.data.length, 24);
    central.writeUInt16LE(nameBytes.length, 28);
    central.writeUInt32LE(offset, 42);
    centralChunks.push(central, nameBytes);

    offset += local.length + nameBytes.length + raw.length;
  }
  const centralDirectory = Buffer.concat(centralChunks);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralDirectory.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...localChunks, centralDirectory, end]);
}

const bigChapter = sampleText(60 * 1024);
const syntheticZip = buildZip([
  { name: "mimetype", data: Buffer.from("application/epub+zip"), compress: false },
  { name: "META-INF/container.xml", data: Buffer.from("<container/>".repeat(200)), compress: true },
  { name: "OEBPS/text/chapter1.xhtml", data: bigChapter, compress: true },
]);
const syntheticEntries = readZip(syntheticZip);
check("synthetic zip entry count", syntheticEntries.length === 3, `got ${syntheticEntries.length}`);
check(
  "synthetic stored entry",
  zipEntryData(syntheticZip, syntheticEntries[0]).toString() === "application/epub+zip",
);
check(
  "synthetic deflate entry",
  zipEntryData(syntheticZip, syntheticEntries[1]).toString() === "<container/>".repeat(200),
);
check(
  "synthetic large deflate entry",
  zipEntryData(syntheticZip, syntheticEntries[2]).equals(bigChapter),
  `expected ${bigChapter.length} bytes, got ${zipEntryData(syntheticZip, syntheticEntries[2]).length}`,
);

console.log("4) 真实 EPUB（PowerShell Compress-Archive 生成）");
const epubPath = path.resolve("Tools/tmp/sample.epub");
if (fs.existsSync(epubPath)) {
  const buffer = fs.readFileSync(epubPath);
  const entries = readZip(buffer);
  check("epub entry count > 0", entries.length > 0, `got ${entries.length}`);
  let allMatch = true;
  let detail = "";
  for (const entry of entries) {
    if (entry.path.endsWith("/")) continue;
    const extracted = zipEntryData(buffer, entry);
    const onDisk = path.resolve("Tools/tmp/sample_src", entry.path);
    if (!fs.existsSync(onDisk)) {
      allMatch = false;
      detail = `missing ${entry.path}`;
      break;
    }
    if (Buffer.compare(extracted, fs.readFileSync(onDisk)) !== 0) {
      allMatch = false;
      detail = `content mismatch ${entry.path}`;
      break;
    }
  }
  check("epub entries match on-disk originals", allMatch, detail);
} else {
  console.log("  skip 没有找到 Tools/tmp/sample.epub");
}

console.log(failures === 0 ? "\n全部通过" : `\n失败 ${failures} 项`);
process.exit(failures === 0 ? 0 : 1);
