// ZipArchive.swift 的等价 JS 移植，仅用于算法验证。
import { Inflate } from "./inflate-port.mjs";

function u16(bytes, offset) {
  if (offset < 0 || offset + 2 > bytes.length) throw new Error("read out of range (u16)");
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function u32(bytes, offset) {
  if (offset < 0 || offset + 4 > bytes.length) throw new Error("read out of range (u32)");
  return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
}

function u64(bytes, offset) {
  if (offset < 0 || offset + 8 > bytes.length) throw new Error("read out of range (u64)");
  let value = 0;
  for (let index = 7; index >= 0; index -= 1) {
    value = value * 256 + bytes[offset + index];
  }
  return value;
}

export function sanitizedPath(raw) {
  const normalized = raw.replace(/\\/g, "/");
  const isDirectory = normalized.endsWith("/");
  const components = normalized
    .split("/")
    .filter((component) => component.length > 0 && component !== "." && component !== "..");
  if (components.length === 0) return null;
  return components.join("/") + (isDirectory ? "/" : "");
}

function findEndOfCentralDirectory(bytes) {
  const minimum = 22;
  if (bytes.length < minimum) throw new Error("not a zip file");
  const lowest = Math.max(0, bytes.length - minimum - 65535);
  let offset = bytes.length - minimum;
  while (offset >= lowest) {
    if (bytes[offset] === 0x50 && bytes[offset + 1] === 0x4b && bytes[offset + 2] === 0x05 && bytes[offset + 3] === 0x06) {
      return offset;
    }
    offset -= 1;
  }
  throw new Error("not a zip file");
}

function zip64EndOfCentralDirectory(bytes, eocd) {
  const locator = eocd - 20;
  if (locator < 0 || u32(bytes, locator) !== 0x07064b50) throw new Error("missing zip64 locator");
  const recordOffset = u64(bytes, locator + 8);
  if (u32(bytes, recordOffset) !== 0x06064b50) throw new Error("bad zip64 record");
  return { entryCount: u64(bytes, recordOffset + 32), directoryOffset: u64(bytes, recordOffset + 48) };
}

function zip64ExtraValues(extra, wantsUncompressed, wantsCompressed, wantsOffset) {
  let cursor = 0;
  while (cursor + 4 <= extra.length) {
    const fieldID = extra[cursor] | (extra[cursor + 1] << 8);
    const fieldSize = extra[cursor + 2] | (extra[cursor + 3] << 8);
    const payloadStart = cursor + 4;
    if (payloadStart + fieldSize > extra.length) break;
    if (fieldID === 0x0001) {
      let payload = payloadStart;
      const result = { uncompressedSize: null, compressedSize: null, localHeaderOffset: null };
      if (wantsUncompressed) {
        result.uncompressedSize = u64(extra, payload);
        payload += 8;
      }
      if (wantsCompressed) {
        result.compressedSize = u64(extra, payload);
        payload += 8;
      }
      if (wantsOffset) {
        result.localHeaderOffset = u64(extra, payload);
        payload += 8;
      }
      return result;
    }
    cursor = payloadStart + fieldSize;
  }
  throw new Error("missing zip64 extra field");
}

export function readZip(buffer) {
  const bytes = [...buffer];
  const eocd = findEndOfCentralDirectory(bytes);
  let entryCount = u16(bytes, eocd + 10);
  let directoryOffset = u32(bytes, eocd + 16);
  if (entryCount === 0xffff || directoryOffset === 0xffffffff) {
    const zip64 = zip64EndOfCentralDirectory(bytes, eocd);
    entryCount = zip64.entryCount;
    directoryOffset = zip64.directoryOffset;
  }

  let cursor = directoryOffset;
  const entries = [];
  for (let index = 0; index < entryCount; index += 1) {
    if (u32(bytes, cursor) !== 0x02014b50) throw new Error("bad central directory signature");
    const flags = u16(bytes, cursor + 8);
    const method = u16(bytes, cursor + 10);
    let compressedSize = u32(bytes, cursor + 20);
    let uncompressedSize = u32(bytes, cursor + 24);
    const nameLength = u16(bytes, cursor + 28);
    const extraLength = u16(bytes, cursor + 30);
    const commentLength = u16(bytes, cursor + 32);
    let localHeaderOffset = u32(bytes, cursor + 42);
    const recordLength = 46 + nameLength + extraLength + commentLength;
    if (cursor + recordLength > bytes.length) throw new Error("central directory record out of range");
    const name = Buffer.from(bytes.slice(cursor + 46, cursor + 46 + nameLength)).toString("utf8");

    if (compressedSize === 0xffffffff || uncompressedSize === 0xffffffff || localHeaderOffset === 0xffffffff) {
      const extraStart = cursor + 46 + nameLength;
      const extra = bytes.slice(extraStart, extraStart + extraLength);
      const values = zip64ExtraValues(
        extra,
        uncompressedSize === 0xffffffff,
        compressedSize === 0xffffffff,
        localHeaderOffset === 0xffffffff,
      );
      if (values.uncompressedSize !== null) uncompressedSize = values.uncompressedSize;
      if (values.compressedSize !== null) compressedSize = values.compressedSize;
      if (values.localHeaderOffset !== null) localHeaderOffset = values.localHeaderOffset;
    }
    if ((flags & 0x0001) !== 0) throw new Error("encrypted entry");
    entries.push({ path: name, method, compressedSize, uncompressedSize, localHeaderOffset });
    cursor += recordLength;
  }
  return entries;
}

export function zipEntryData(buffer, entry) {
  const bytes = [...buffer];
  const header = entry.localHeaderOffset;
  if (u32(bytes, header) !== 0x04034b50) throw new Error("bad local header signature");
  const nameLength = u16(bytes, header + 26);
  const extraLength = u16(bytes, header + 28);
  const start = header + 30 + nameLength + extraLength;
  if (start + entry.compressedSize > bytes.length) throw new Error("entry data out of range");
  const payload = bytes.slice(start, start + entry.compressedSize);
  if (entry.method === 0) return Buffer.from(payload);
  if (entry.method === 8) return Inflate.decompress(payload, entry.uncompressedSize);
  throw new Error(`unsupported compression method ${entry.method}`);
}
