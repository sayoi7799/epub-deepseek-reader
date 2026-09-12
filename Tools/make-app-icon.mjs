// 生成 App 图标（书架主题）：1024x1024、不透明、无圆角（iOS 自己会裁圆角）。
// 用代码画而不是用图片素材，好处是配色和形状可以精确控制、随时可改、可复现。
//   用法：node Tools/make-app-icon.mjs
//   输出：EPUBTranslator/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//         EPUBTranslator/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const SIZE = 1024;
const SS = 3; // 超采样倍率：先在 3072 上硬边绘制，再缩小到 1024 得到抗锯齿
const W = SIZE * SS;

// ---------------------------------------------------------------- 画布工具

function createCanvas(bg) {
  const buf = new Float32Array(W * W * 3);
  for (let i = 0; i < W * W; i += 1) {
    buf[i * 3] = bg[0];
    buf[i * 3 + 1] = bg[1];
    buf[i * 3 + 2] = bg[2];
  }
  return buf;
}

function hex(value) {
  const v = value.replace("#", "");
  return [
    parseInt(v.slice(0, 2), 16) / 255,
    parseInt(v.slice(2, 4), 16) / 255,
    parseInt(v.slice(4, 6), 16) / 255,
  ];
}

/// 竖直渐变（可带一点斜向），from 在上、to 在下。
function paintGradient(buf, fromHex, toHex, tiltX = 0.25) {
  const from = hex(fromHex);
  const to = hex(toHex);
  for (let y = 0; y < W; y += 1) {
    for (let x = 0; x < W; x += 1) {
      const t = Math.min(1, Math.max(0, (y / W) * (1 - tiltX) + (x / W) * tiltX));
      const i = (y * W + x) * 3;
      buf[i] = from[0] + (to[0] - from[0]) * t;
      buf[i + 1] = from[1] + (to[1] - from[1]) * t;
      buf[i + 2] = from[2] + (to[2] - from[2]) * t;
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

/// 径向光晕（柔和的中心发亮）。
function paintGlow(buf, cx, cy, radius, color, maxAlpha) {
  for (let y = Math.max(0, Math.floor(cy - radius)); y <= Math.min(W - 1, Math.ceil(cy + radius)); y += 1) {
    for (let x = Math.max(0, Math.floor(cx - radius)); x <= Math.min(W - 1, Math.ceil(cx + radius)); x += 1) {
      const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy) / radius;
      if (d >= 1) continue;
      const falloff = (1 - d) * (1 - d);
      blendPixel(buf, x, y, color, maxAlpha * falloff);
    }
  }
}

/// 圆角矩形，支持旋转（图书馆的书脊、隔板都用它）。
function fillRoundedRect(buf, cx, cy, w, h, radius, angleDeg, color, alpha = 1) {
  const rad = (angleDeg * Math.PI) / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  const hw = w / 2;
  const hh = h / 2;
  const bound = Math.ceil(Math.hypot(w, h) / 2) + 2;
  const x0 = Math.max(0, Math.floor(cx - bound));
  const x1 = Math.min(W - 1, Math.ceil(cx + bound));
  const y0 = Math.max(0, Math.floor(cy - bound));
  const y1 = Math.min(W - 1, Math.ceil(cy + bound));
  for (let y = y0; y <= y1; y += 1) {
    for (let x = x0; x <= x1; x += 1) {
      const dx = x + 0.5 - cx;
      const dy = y + 0.5 - cy;
      const lx = dx * cos + dy * sin;
      const ly = -dx * sin + dy * cos;
      const qx = Math.abs(lx) - (hw - radius);
      const qy = Math.abs(ly) - (hh - radius);
      const d =
        Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - radius;
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
      if (inside > 0) {
        blendPixel(buf, x, y, color, alpha * (inside / offsets.length));
      }
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

/** 把高分辨率画布缩小到 SIZE×SIZE，顺手完成抗锯齿。 */
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
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
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

/** 所有坐标都按 1024 设计，这里统一乘 SS 到高分辨率画布。 */
const S = (value) => value * SS;

function drawIcon({ dark }) {
  const palette = dark
    ? {
        bgTop: "#1B2440",
        bgBottom: "#0A0E1C",
        glow: 0.10,
        shelf: "#D8CDB4",
        shelfEdge: "#9A8F76",
        books: ["#C9924C", "#DCCFB2", "#B06F79", "#D3BB8C", "#C99B57", "#DCCFB2"],
        ribbon: "#C25F5F",
        shadow: 0.5,
      }
    : {
        bgTop: "#3B63D6",
        bgBottom: "#182253",
        glow: 0.16,
        shelf: "#F6EEDC",
        shelfEdge: "#C4B393",
        books: ["#E3A855", "#F5EAD2", "#CB7B86", "#EBD49F", "#E8B96A", "#F5EAD2"],
        ribbon: "#D9695F",
        shadow: 0.34,
      };

  const canvas = createCanvas(hex(palette.bgTop));
  paintGradient(canvas, palette.bgTop, palette.bgBottom, 0.28);
  paintGlow(canvas, S(512), S(300), S(760), hex("#FFFFFF"), palette.glow);

  const white = hex("#FFFFFF");
  const black = hex("#000000");

  // 隔板下方的投影，让书和板子“立”起来
  fillEllipse(canvas, S(512), S(706), S(344), S(26), black, palette.shadow);

  // 书架隔板
  fillRoundedRect(canvas, S(512), S(664), S(672), S(32), S(16), 0, hex(palette.shelf), 1);
  fillRoundedRect(canvas, S(512), S(684), S(672), S(12), S(6), 0, hex(palette.shelfEdge), 0.65);

  const standingBottom = 648;

  // 立着的书（左半边）
  const standing = [
    { cx: 288, w: 84, top: 372 },
    { cx: 382, w: 92, top: 322 },
    { cx: 484, w: 78, top: 400 },
  ];
  standing.forEach((book, index) => {
    const height = standingBottom - book.top;
    fillRoundedRect(
      canvas,
      S(book.cx),
      S(book.top + height / 2),
      S(book.w),
      S(height),
      S(10),
      0,
      hex(palette.books[index]),
      1,
    );
    // 书脊上的书名标签（书的经典特征）
    fillRoundedRect(
      canvas,
      S(book.cx),
      S(book.top + height * 0.26),
      S(book.w - 28),
      S(book.w * 0.3),
      S(book.w * 0.09),
      0,
      white,
      0.5,
    );
    // 底部一道浅色压印
    fillRoundedRect(
      canvas,
      S(book.cx),
      S(standingBottom - 44),
      S(book.w - 30),
      S(8),
      S(4),
      0,
      white,
      0.26,
    );
  });

  // 中间那本书挂一条书签带
  fillPolygon(
    canvas,
    [
      [S(365), S(330)],
      [S(399), S(330)],
      [S(399), S(486)],
      [S(382), S(462)],
      [S(365), S(486)],
    ],
    hex(palette.ribbon),
    1,
  );

  // 斜靠的一本书
  fillRoundedRect(canvas, S(606), S(492), S(82), S(320), S(11), -13, hex(palette.books[3]), 1);
  fillRoundedRect(canvas, S(606), S(410), S(52), S(9), S(4), -13, white, 0.3);

  // 右半边：平放的两本书
  fillRoundedRect(canvas, S(726), S(630), S(190), S(38), S(14), 0, hex(palette.books[4]), 1);
  fillRoundedRect(canvas, S(726), S(592), S(172), S(34), S(12), 0, hex(palette.books[5]), 1);
  fillRoundedRect(canvas, S(726), S(586), S(120), S(7), S(3.5), 0, white, 0.3);

  // 隔板本身的高光边
  fillRoundedRect(canvas, S(512), S(652), S(664), S(5), S(2.5), 0, white, 0.32);

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

// 终端里打印一张低分辨率预览，方便在没有图片查看器时确认构图。
function asciiPreview(rgba, cols = 72, rows = 34) {
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

/// 按颜色分类的预览：'.' 背景蓝、'W' 米白/白、'A' 琥珀、'R' red-ish、'B' 亮蓝
function semanticPreview(rgba, cols = 72, rows = 34) {
  const lines = [];
  for (let r = 0; r < rows; r += 1) {
    let line = "";
    for (let c = 0; c < cols; c += 1) {
      let rr = 0;
      let gg = 0;
      let bb = 0;
      let count = 0;
      const y0 = Math.floor((r * SIZE) / rows);
      const y1 = Math.max(y0 + 1, Math.floor(((r + 1) * SIZE) / rows));
      const x0 = Math.floor((c * SIZE) / cols);
      const x1 = Math.max(x0 + 1, Math.floor(((c + 1) * SIZE) / cols));
      for (let y = y0; y < y1; y += 1) {
        for (let x = x0; x < x1; x += 1) {
          const i = (y * SIZE + x) * 4;
          rr += rgba[i] / 255;
          gg += rgba[i + 1] / 255;
          bb += rgba[i + 2] / 255;
          count += 1;
        }
      }
      rr /= count;
      gg /= count;
      bb /= count;
      const lum = 0.2126 * rr + 0.7152 * gg + 0.0722 * bb;
      let ch;
      if (bb > rr + 0.04 && lum < 0.55) ch = ".";
      else if (lum > 0.82) ch = "W";
      else if (rr > gg + 0.06 && rr > 0.55) ch = "A";
      else if (rr > bb + 0.15 && lum < 0.75) ch = "R";
      else if (lum > 0.62) ch = "w";
      else ch = "o";
      line += ch;
    }
    lines.push(line);
  }
  return lines.join("\n");
}

const previewIcon = drawIcon({ dark: false });
console.log("\n浅色版亮度预览：\n" + asciiPreview(previewIcon));
console.log("\n浅色版颜色预览（. 背景 / W 米白 / A 琥珀 / R 红 / w 中间调）：\n" + semanticPreview(previewIcon));

// 自己在终端里看不到图片，所以额外打印几个关键位置的像素值来验证每一层都画上去了。
function probe(rgba, x, y, label) {
  const i = (y * SIZE + x) * 4;
  console.log(`  ${label.padEnd(12)} (${x},${y}) = rgb(${rgba[i]}, ${rgba[i + 1]}, ${rgba[i + 2]})`);
}
console.log("\n关键位置采样（浅色版）：");
probe(previewIcon, 60, 60, "背景左上");
probe(previewIcon, 288, 444, "书1 标签");
probe(previewIcon, 288, 560, "书1 书脊");
probe(previewIcon, 382, 400, "书签带");
probe(previewIcon, 382, 560, "书2 书脊");
probe(previewIcon, 484, 560, "书3 书脊");
probe(previewIcon, 606, 500, "斜靠书");
probe(previewIcon, 726, 630, "平放书");
probe(previewIcon, 512, 664, "隔板");
probe(previewIcon, 512, 730, "板下背景");
