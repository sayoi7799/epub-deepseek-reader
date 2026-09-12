// 没有 Xcode 的情况下的静态自检：
// 1) 括号/花括号是否配平
// 2) 是否有重复声明的类型
// 3) `变量.成员` 里的成员是否真的存在于该变量的类型上
import fs from "node:fs";
import path from "node:path";

const roots = ["EPUBTranslator", "EPUBTranslatorWidgets", "Shared"].map((dir) => path.resolve(dir));
const root = roots[0];

function listSwiftFiles(dir) {
  const result = [];
  if (!fs.existsSync(dir)) return result;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) result.push(...listSwiftFiles(full));
    else if (entry.name.endsWith(".swift")) result.push(full);
  }
  return result;
}

function displayPath(file) {
  const relative = path.relative(root, file);
  if (!relative.startsWith("..")) return relative;
  return path.relative(path.resolve("."), file);
}

/// 把注释与字符串字面量替换成空格，保留原始长度以便定位。
function strip(source) {
  let out = "";
  let i = 0;
  const n = source.length;
  const push = (ch) => {
    out += ch === "\n" ? "\n" : " ";
  };
  while (i < n) {
    const c = source[i];
    const next = source[i + 1];

    if (c === "/" && next === "/") {
      while (i < n && source[i] !== "\n") {
        push(source[i]);
        i += 1;
      }
      continue;
    }
    if (c === "/" && next === "*") {
      let depth = 1;
      push(source[i]);
      push(source[i + 1]);
      i += 2;
      while (i < n && depth > 0) {
        if (source[i] === "/" && source[i + 1] === "*") {
          depth += 1;
          push(source[i]);
          push(source[i + 1]);
          i += 2;
          continue;
        }
        if (source[i] === "*" && source[i + 1] === "/") {
          depth -= 1;
          push(source[i]);
          push(source[i + 1]);
          i += 2;
          continue;
        }
        push(source[i]);
        i += 1;
      }
      continue;
    }

    // 原始字符串 #"..."# / #"""..."""#
    if (c === "#") {
      let hashes = 0;
      while (source[i + 1 + hashes] === "#") hashes += 1;
      if (source[i + 1 + hashes] === '"') {
        const marker = "#".repeat(hashes + 1);
        push(source[i]);
        i += 1;
        while (i < n) {
          if (source.startsWith(marker + '"', i)) {
            for (let k = 0; k < marker.length + 1; k += 1) push(source[i + k]);
            i += marker.length + 1;
            break;
          }
          push(source[i]);
          i += 1;
        }
        continue;
      }
    }

    if (c === '"') {
      const isMultiline = source.startsWith('"""', i);
      const terminator = isMultiline ? '"""' : '"';
      for (let k = 0; k < terminator.length; k += 1) push(source[i + k]);
      i += terminator.length;
      while (i < n) {
        if (!isMultiline && source[i] === "\\") {
          push(source[i]);
          push(source[i + 1]);
          i += 2;
          continue;
        }
        if (source.startsWith(terminator, i)) {
          for (let k = 0; k < terminator.length; k += 1) push(source[i + k]);
          i += terminator.length;
          break;
        }
        push(source[i]);
        i += 1;
      }
      continue;
    }

    out += c;
    i += 1;
  }
  return out;
}

function matchBrace(code, openIndex) {
  let depth = 0;
  for (let i = openIndex; i < code.length; i += 1) {
    if (code[i] === "{") depth += 1;
    else if (code[i] === "}") {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return -1;
}

const files = roots.flatMap(listSwiftFiles);
const problems = [];

// ---- 1) 配平检查 ----
for (const file of files) {
  const code = strip(fs.readFileSync(file, "utf8"));
  const pairs = [
    ["{", "}"],
    ["(", ")"],
    ["[", "]"],
  ];
  for (const [open, close] of pairs) {
    const openCount = [...code].filter((c) => c === open).length;
    const closeCount = [...code].filter((c) => c === close).length;
    if (openCount !== closeCount) {
      problems.push(`${displayPath(file)}: ${open}${close} 不配平 (${openCount} vs ${closeCount})`);
    }
  }
}

// ---- 2) 类型声明与成员收集 ----
const declaredTypes = new Map(); // name -> [files]
const allTypeNames = new Set(); // 包含嵌套类型，用于构造调用检查
const members = new Map(); // name -> Set(member)

function collectMembers(typeName, body) {
  const set = members.get(typeName) ?? new Set();
  const patterns = [
    /\bfunc\s+([A-Za-z_]\w*)/g,
    /\b(?:let|var)\s+([A-Za-z_]\w*)/g,
    /\bcase\s+([A-Za-z_]\w*)/g,
    /\b(?:let|var)\s+([A-Za-z_]\w*)\s*[:(]/g,
  ];
  for (const pattern of patterns) {
    for (const match of body.matchAll(pattern)) set.add(match[1]);
  }
  // 枚举里一个 case 行可能有多个成员：case a, b, c
  for (const match of body.matchAll(/\bcase\s+([A-Za-z_][\w\s,]*)\(?/g)) {
    for (const name of match[1].split(",")) {
      const trimmed = name.trim().split(/[\s(]/)[0];
      if (/^[A-Za-z_]\w*$/.test(trimmed)) set.add(trimmed);
    }
  }
  members.set(typeName, set);
}

for (const file of files) {
  const code = strip(fs.readFileSync(file, "utf8"));
  const relative = displayPath(file);

  // 只统计顶层类型（行首无缩进），避免把嵌套类型误判成重复声明。
  for (const match of code.matchAll(/^(?:public |internal |final |open )*(?:class|struct|enum|actor|protocol)\s+([A-Z]\w*)/gm)) {
    const name = match[1];
    const list = declaredTypes.get(name) ?? [];
    list.push(relative);
    declaredTypes.set(name, list);
  }
  for (const match of code.matchAll(/\b(?:class|struct|enum|actor|protocol)\s+([A-Z]\w*)/g)) {
    allTypeNames.add(match[1]);
  }

  // 类型主体 + extension 主体
  const bodyPattern = /\b(?:class|struct|enum|actor|protocol|extension)\s+([A-Z]\w*)[^{]*\{/g;
  for (const match of code.matchAll(bodyPattern)) {
    const name = match[1];
    const openIndex = match.index + match[0].length - 1;
    const closeIndex = matchBrace(code, openIndex);
    if (closeIndex < 0) continue;
    collectMembers(name, code.slice(openIndex, closeIndex));
  }
}

for (const [name, list] of declaredTypes) {
  if (list.length > 1) {
    problems.push(`类型 ${name} 被声明了 ${list.length} 次：${list.join(", ")}`);
  }
}

// ---- 3) 成员访问检查 ----
const skipTypes = new Set(["Task", "URL", "Data", "Date", "String", "Array", "Set", "Dictionary", "Result", "Error"]);

for (const file of files) {
  const code = strip(fs.readFileSync(file, "utf8"));
  const relative = displayPath(file);

  const variables = new Map();
  for (const match of code.matchAll(/\b(?:let|var)\s+([a-z_]\w*)\s*:\s*([A-Z]\w*)/g)) {
    variables.set(match[1], match[2]);
  }
  for (const match of code.matchAll(/\b(?:let|var)\s+([a-z_]\w*)\s*=\s*([A-Z]\w*)\(/g)) {
    variables.set(match[1], match[2]);
  }

  for (const match of code.matchAll(/\b([a-z_]\w*)\.([A-Za-z_]\w*)/g)) {
    const [, variable, member] = match;
    const typeName = variables.get(variable);
    if (!typeName) continue;
    if (skipTypes.has(typeName)) continue;
    const known = members.get(typeName);
    if (!known) continue;
    if (known.has(member)) continue;
    if (["rawValue", "allCases", "init", "self", "Type"].includes(member)) continue;
    // 协议/父类提供、或 Swift 语法糖，先记录下来人工判断
    problems.push(`${relative}: ${variable}(${typeName}).${member} 未在类型上找到`);
  }
}

// ---- 4) 构造调用检查：Foo(...) 里的 Foo 是否是自己声明的类型或已知系统类型 ----
const systemTypes = new Set([
  // Swift / Foundation
  "String", "Substring", "Character", "Int", "Int8", "Int16", "Int32", "Int64", "UInt",
  "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float", "Bool", "Array", "Set",
  "Dictionary", "Optional", "Result", "Error", "Range", "ClosedRange", "Void",
  "URL", "URLRequest", "URLSession", "URLComponents", "Data", "Date", "UUID", "Locale",
  "JSONDecoder", "JSONEncoder", "JSONSerialization", "PropertyListSerialization",
  "NSRegularExpression", "NSRange", "NSNumber", "NSString", "Scanner", "FileManager",
  "UserDefaults", "DateFormatter", "NumberFormatter", "XMLParser", "NSPredicate",
  "NotificationCenter", "CGRect", "CGSize", "CGPoint", "CGFloat", "NSTemporaryDirectory",
  "AsyncThrowingStream", "AsyncStream", "Task", "MainActor", "DispatchQueue",
  // SwiftUI
  "Color", "Capsule", "RoundedRectangle", "Rectangle", "Circle", "Ellipse", "ProgressView",
  "Text", "Image", "Label", "Button", "Slider", "Toggle", "Picker", "Section", "Form",
  "List", "ForEach", "ScrollView", "LazyVGrid", "GridItem", "NavigationStack", "TabView",
  "NavigationLink", "Binding", "State", "Environment", "Bindable", "ShareLink",
  "LabeledContent", "ContentUnavailableView", "LinearGradient", "Menu", "SecureField",
  "TextField", "TextEditor", "Divider", "Spacer", "Group", "GeometryReader", "AnyView",
  "StrokeStyle", "SharePreview", "ColorScheme", "Animation", "DragGesture", "ToolbarItem",
  "ToolbarItemGroup", "ScrollViewReader", "Stepper", "Link", "Alert",
  "VStack", "HStack", "ZStack", "EmptyView", "LazyVStack", "LazyHStack", "ViewThatFits",
  // UIKit
  "UIApplication", "UIPasteboard", "UIImage", "UIColor", "UIFont", "UIView",
  // AppIntents
  "AppShortcut", "IntentDescription", "TypeDisplayRepresentation", "DisplayRepresentation",
  "LocalizedStringResource", "Summary", "AppShortcutsProvider", "Parameter", "AppEnum",
  // WebKit
  "WKWebView", "WKWebViewConfiguration", "WKWebpagePreferences", "WKUserContentController",
  // Security
  "SecItemAdd", "SecItemCopyMatching", "SecItemDelete",
  // Other
  "CryptoKit", "SHA256", "Observation", "UniformTypeIdentifiers", "UTType", "NSObject",
  // ActivityKit / WidgetKit
  "Activity", "ActivityContent", "ActivityAuthorizationInfo", "ActivityAttributes",
  "ActivityConfiguration", "ActivityViewContext", "ActivityUIDismissalPolicy",
  "AlertConfiguration", "DynamicIsland", "DynamicIslandExpandedRegion", "Widget",
  "WidgetBundle", "WidgetConfiguration", "PushType",
]);

for (const file of files) {
  const code = strip(fs.readFileSync(file, "utf8"));
  const relative = displayPath(file);
  for (const match of code.matchAll(/(?<![.\w])([A-Z][A-Za-z0-9_]*)\(/g)) {
    const name = match[1];
    if (allTypeNames.has(name) || systemTypes.has(name)) continue;
    problems.push(`${relative}: 构造调用 ${name}(...) 找不到对应类型`);
  }
}

if (problems.length === 0) {
  console.log(`检查了 ${files.length} 个 Swift 文件：没有发现问题。`);
} else {
  console.log(`检查了 ${files.length} 个 Swift 文件，发现 ${problems.length} 条待确认：`);
  for (const problem of problems) console.log(`  - ${problem}`);
}
