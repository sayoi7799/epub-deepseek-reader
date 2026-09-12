// 生成 App 图标：黑白配色的"翻开的书"。1024x1024、不透明、无圆角（iOS 自己裁圆角）。
// 用代码画而不是用图片素材：配色和形状可以精确控制，随时可改，也能自我验证。
//   用法：node Tools/make-app-icon.mjs
//   输出：EPUBTranslator/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png（白底黑书）
//         EPUBTranslator/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png（黑底白书）
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const SIZE = 1024;
const SS = 3; // 先在 3072 上硬边绘制，再缩小到 1024，得到平滑边缘
const W = SIZE * SS;

// ---------------------------------------------------------------- 画布工具

function hex(value) {
  const v = value.replace("#", "");
  return [
    parseInt(v.slice(0, 2), 16) / 255,
    parseInt(v.slice(2, 4), 16) / 255,
    parseInt(v.slice(4, 6), 16) / 255,
  ];
}

function createCanvas(color) {
  const buf = new Float32Array(W * W * 3);
  for (let i = 0; i < W * W; i += 1) {
    buf[i * 3] = color[0];
    buf[i * 3 + 1] = color[1];
    buf[i * 3 + 2] = color[2];
  }
  return buf;
}

function paintGradient(buf, fromHex, toHex) {
  const from = hex(fromHex);
  const to = hex(toHex);
  for (let y = 0; y < W; y += 1) {
    const t = y / (W - 1);
    const r = from[0] + (to[0] - from[0]) * t;
    const g = from[1] + (to[1] - from[1]) * t;
    const b = from[2] + (to[2] - from[2]) * t;
    for (let x = 0; x < W; x += 1) {
      const i = (y * W + x) * 3;
      buf[i] = r;
      buf[i + 1] = g;
      buf[i + 2] = b;
    }
  }
}

function blendPixel(buf, x, y, color, alpha) {
  if (alpha <= 0 || x < 0 || y < 0 || x >= W || y >= W) return;
  const a = Math.min(1, alpha);
  const i = (y * W + x) * 3;
  const ia = 1 - a;
  buf[i] = buf[i] * ia + color[0] * a;
  buf[i + 1] = buf[i + 1] * ia + color[1] * a;
  buf[i + 2] = buf[i + 2] * ia + color[2] * a;
}

function paintGlow(buf, cx, cy, radius, color, maxAlpha) {
  for (let y = Math.max(0, Math.floor(cy - radius)); y <= Math.min(W - 1, Math.ceil(cy + radius)); y += 1) {
    for (let x = Math.max(0, Math.floor(cx - radius)); x <= Math.min(W - 1, Math.ceil(cx + radius)); x += 1) {
      const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy) / radius;
      if (d >= 1) continue;
      blendPixel(buf, x, y, color, maxAlpha * (1 - d) * (1 - d));
    }
  }
}

function fillRoundedRect(buf, cx, cy, w, h, radius, angleDeg, color, alpha = 1) {
  const rad = (angleDeg * Math.PI) / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  const hw = w / 2;
  const hh = h / 2;
  const bound = Math.ceil(Math.hypot(w, h) / 2) + 2;
  for (let y = Math.max(0, Math.floor(cy - bound)); y <= Math.min(W - 1, Math.ceil(cy + bound)); y += 1) {
    for (let x = Math.max(0, Math.floor(cx - bound)); x <= Math.min(W - 1, Math.ceil(cx + bound)); x += 1) {
      const dx = x + 0.5 - cx;
      const dy = y + 0.5 - cy;
      const lx = dx * cos + dy * sin;
      const ly = -dx * sin + dy * cos;
      const qx = Math.abs(lx) - (hw - radius);
      const qy = Math.abs(ly) - (hh - radius);
      const d = Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - radius;
      const cov = Math.min(1, Math.max(0, 0.5 - d));
      if (cov > 0) blendPixel(buf, x, y, color, alpha * cov);
    }
  }
}

function fillPolygon(buf, points, color, alpha = 1) {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const [px, py] of points) {
    minX = Math.min(minX, px);
    minY = Math.min(minY, py);
    maxX = Math.max(maxX, px);
    maxY = Math.max(maxY, py);
  }
  const x0 = Math.max(0, Math.floor(minX));
  const x1 = Math.min(W - 1, Math.ceil(maxX));
  const y0 = Math.max(0, Math.floor(minY));
  const y1 = Math.min(W - 1, Math.ceil(maxY));
  const offsets = [
    [0.25, 0.25],
    [0.75, 0.25],
    [0.25, 0.75],
    [0.75, 0.75],
  ];
  for (let y = y0; y <= y1; y += 1) {
    for (let x = x0; x <= x1; x += 1) {
      let inside = 0;
      for (const [ox, oy] of offsets) {
        const px = x + ox;
        const py = y + oy;
        let hit = false;
        for (let i = 0, j = points.length - 1; i < points.length; j = i, i += 1) {
          const [xi, yi] = points[i];
          const [xj, yj] = points[j];
          if (yi > py !== yj > py && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) {
            hit = !hit;
          }
        }
        if (hit) inside += 1;
      }
      if (inside > 0) blendPixel(buf, x, y, color, alpha * (inside / offsets.length));
    }
  }
}

function fillEllipse(buf, cx, cy, rx, ry, color, maxAlpha) {
  for (let y = Math.max(0, Math.floor(cy - ry)); y <= Math.min(W - 1, Math.ceil(cy + ry)); y += 1) {
    for (let x = Math.max(0, Math.floor(cx - rx)); x <= Math.min(W - 1, Math.ceil(cx + rx)); x += 1) {
      const d = Math.hypot((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry);
      if (d >= 1) continue;
      blendPixel(buf, x, y, color, maxAlpha * Math.pow(1 - d, 1.6));
    }
  }
}

function downsample(buf) {
  const out = Buffer.alloc(SIZE * SIZE * 4);
  const samples = SS * SS;
  for (let y = 0; y < SIZE; y += 1) {
    for (let x = 0; x < SIZE; x += 1) {
      let r = 0;
      let g = 0;
      let b = 0;
      for (let sy = 0; sy < SS; sy += 1) {
        for (let sx = 0; sx < SS; sx += 1) {
          const i = ((y * SS + sy) * W + (x * SS + sx)) * 3;
          r += buf[i];
          g += buf[i + 1];
          b += buf[i + 2];
        }
      }
      const o = (y * SIZE + x) * 4;
      out[o] = Math.round((r / samples) * 255);
      out[o + 1] = Math.round((g / samples) * 255);
      out[o + 2] = Math.round((b / samples) * 255);
      out[o + 3] = 255;
    }
  }
  return out;
}

// ---------------------------------------------------------------- PNG 编码

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (let i = 0; i < buffer.length; i += 1) {
    c = CRC_TABLE[(c ^ buffer[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const typeBuffer = Buffer.from(type, "ascii");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 0);
  return Buffer.concat([length, typeBuffer, data, crc]);
}

function encodePNG(rgba, width, height) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0; // filter: none
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

// ---------------------------------------------------------------- 图标绘制

/// 坐标按 1024 设计，这里统一放大到绘制分辨率。
const S = (value) => value * SS;

/**
 * 一页纸的形状：从书脊往外，上边略微上扬、下边向书脊下沉，
 * 这样两页合起来就是"翻开的书"的蝴蝶形。
 */
function pageOutline(sign, {
  innerTop = 386,
  outerTop = 348,
  innerBottom = 692,
  outerBottom = 634,
  innerX = 13,
  outerX = 284,
  steps = 10,
} = {}) {
  const points = [];
  for (let i = 0; i <= steps; i += 1) {
    const t = i / steps;
    const x = 512 + sign * (innerX + (outerX - innerX) * t);
    const y = innerTop + (outerTop - innerTop) * Math.pow(t, 0.85);
    points.push([S(x), S(y)]);
  }
  for (let i = steps; i >= 0; i -= 1) {
    const t = i / steps;
    const x = 512 + sign * (innerX + (outerX - innerX) * t);
    const y = innerBottom + (outerBottom - innerBottom) * Math.pow(t, 0.9);
    points.push([S(x), S(y)]);
  }
  return points;
}

function offsetPolygon(points, dy) {
  return points.map(([x, y]) => [x, y + S(dy)]);
}

function drawIcon({ dark }) {
  const palette = dark
    ? { bgTop: "#141414", bgBottom: "#000000", book: "#F2F2F2", page: "#101010", edge: "#9A9A9A", shadow: 0.45 }
    : { bgTop: "#FFFFFF", bgBottom: "#E9E9E9", book: "#141414", page: "#FFFFFF", edge: "#8C8C8C", shadow: 0.16 };

  const canvas = createCanvas(hex(palette.bgTop));
  paintGradient(canvas, palette.bgTop, palette.bgBottom);

  const bookColor = hex(palette.book);
  const pageColor = hex(palette.page);
  const edgeColor = hex(palette.edge);
  const black = hex("#000000");

  // 书底下的软投影，让书"放"在纸面上
  fillEllipse(canvas, S(512), S(726), S(292), S(28), black, palette.shadow);

  const left = pageOutline(-1);
  const right = pageOutline(1);

  // 先画向下偏移 18px 的同一形状，露出的是书页的"厚度"
  fillPolygon(canvas, offsetPolygon(left, 18), edgeColor, 0.95);
  fillPolygon(canvas, offsetPolygon(right, 18), edgeColor, 0.95);

  // 书页本体
  fillPolygon(canvas, left, bookColor, 1);
  fillPolygon(canvas, right, bookColor, 1);

  // 书脊：中间留一条缝，两页分开看
  fillRoundedRect(canvas, S(512), S(539), S(18), S(306), S(9), 0, pageColor, 0.85);

  // 页面上的"文字行"（用底色画，等于在书页上挖出细线）
  const rows = [
    { y: 486, from: 62, to: 232, width: 15 },
    { y: 540, from: 62, to: 200, width: 15 },
    { y: 594, from: 62, to: 218, width: 15 },
  ];
  for (const sign of [-1, 1]) {
    for (const row of rows) {
      const cx = 512 + sign * ((row.from + row.to) / 2);
      const width = row.to - row.from;
      fillRoundedRect(canvas, S(cx), S(row.y), S(width), S(row.width), S(row.width / 2), sign * -6.5, pageColor, 0.62);
    }
  }

  return downsample(canvas);
}

// ---------------------------------------------------------------- 输出

const outDir = path.resolve("EPUBTranslator/Assets.xcassets/AppIcon.appiconset");
fs.mkdirSync(outDir, { recursive: true });

const light = encodePNG(drawIcon({ dark: false }), SIZE, SIZE);
fs.writeFileSync(path.join(outDir, "AppIcon-1024.png"), light);

const dark = encodePNG(drawIcon({ dark: true }), SIZE, SIZE);
fs.writeFileSync(path.join(outDir, "AppIcon-1024-dark.png"), dark);

console.log(`已生成图标：${outDir}`);
console.log(`  AppIcon-1024.png      ${(light.length / 1024).toFixed(0)} KB`);
console.log(`  AppIcon-1024-dark.png ${(dark.length / 1024).toFixed(0)} KB`);

// ---------------------------------------------------------------- 自检
// 我在终端里看不到图片，所以用低分辨率预览 + 像素采样来确认画对了。

function asciiPreview(rgba, cols = 76, rows = 34) {
  const ramp = " .:-=+*#%@";
  const lines = [];
  for (let r = 0; r < rows; r += 1) {
    let line = "";
    for (let c = 0; c < cols; c += 1) {
      let lum = 0;
      let count = 0;
      const y0 = Math.floor((r * SIZE) / rows);
      const y1 = Math.max(y0 + 1, Math.floor(((r + 1) * SIZE) / rows));
      const x0 = Math.floor((c * SIZE) / cols);
      const x1 = Math.max(x0 + 1, Math.floor(((c + 1) * SIZE) / cols));
      for (let y = y0; y < y1; y += 1) {
        for (let x = x0; x < x1; x += 1) {
          const i = (y * SIZE + x) * 4;
          lum += (0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2]) / 255;
          count += 1;
        }
      }
      const value = lum / count;
      line += ramp[Math.min(ramp.length - 1, Math.floor(value * ramp.length))];
    }
    lines.push(line);
  }
  return lines.join("\n");
}

function probe(rgba, x, y, label) {
  const i = (y * SIZE + x) * 4;
  console.log(`  ${label.padEnd(14)} (${x},${y}) = rgb(${rgba[i]}, ${rgba[i + 1]}, ${rgba[i + 2]})`);
}

const previewIcon = drawIcon({ dark: false });
console.log("\n白底黑书预览（@ 最暗、空格最亮）：\n" + asciiPreview(previewIcon));

console.log("\n关键位置采样（浅色版）：");
probe(previewIcon, 40, 40, "背景角落");
probe(previewIcon, 512, 539, "书脊缝");
probe(previewIcon, 256, 470, "左页(黑)");
probe(previewIcon, 380, 486, "左页文字行");
probe(previewIcon, 768, 500, "右页(黑)");
probe(previewIcon, 512, 700, "两页交汇");
probe(previewIcon, 512, 745, "书下投影");
