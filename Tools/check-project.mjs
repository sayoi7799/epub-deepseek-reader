// 检查 Xcode 工程文件的结构：对象 ID 是否合法、引用是否闭合、scheme 是否指向正确的 target。
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(".");
const pbxprojPath = path.join(root, "EPUBTranslator.xcodeproj", "project.pbxproj");
const schemePath = path.join(
  root,
  "EPUBTranslator.xcodeproj",
  "xcshareddata",
  "xcschemes",
  "EPUBTranslator.xcscheme",
);

const pbxproj = fs.readFileSync(pbxprojPath, "utf8");
const scheme = fs.readFileSync(schemePath, "utf8");
const problems = [];

const defined = new Set();
for (const match of pbxproj.matchAll(/^\t\t([0-9A-F]{24})\b/gm)) {
  defined.add(match[1]);
}

// 收集所有形如 <24 位十六进制> 的 token，确认长度与定义一致。
const referenced = new Set();
for (const match of pbxproj.matchAll(/\b([0-9A-F]{20,26})\b/g)) {
  const token = match[1];
  if (token.length !== 24) {
    problems.push(`对象 ID 长度不是 24：${token}`);
    continue;
  }
  referenced.add(token);
}

for (const token of referenced) {
  if (!defined.has(token)) {
    problems.push(`引用了未定义的对象：${token}`);
  }
}

for (const token of defined) {
  if (!referenced.has(token)) {
    problems.push(`定义了但没被引用的对象：${token}`);
  }
}

for (const [open, close] of [["{", "}"], ["(", ")"]]) {
  const openCount = [...pbxproj].filter((c) => c === open).length;
  const closeCount = [...pbxproj].filter((c) => c === close).length;
  if (openCount !== closeCount) {
    problems.push(`project.pbxproj 里 ${open}${close} 不配平（${openCount} vs ${closeCount}）`);
  }
}

const targetMatch = pbxproj.match(/^\t\t([0-9A-F]{24}) \/\* EPUBTranslator \*\/ = \{\n\t\t\tisa = PBXNativeTarget;/m);
if (!targetMatch) {
  problems.push("没有找到 PBXNativeTarget");
} else {
  const targetID = targetMatch[1];
  const blueprint = scheme.match(/BlueprintIdentifier = "([0-9A-F]{24})"/g) ?? [];
  if (blueprint.length === 0) {
    problems.push("scheme 里没有 BlueprintIdentifier");
  }
  for (const entry of blueprint) {
    const value = entry.match(/"([0-9A-F]{24})"/)[1];
    if (value !== targetID) {
      problems.push(`scheme 的 BlueprintIdentifier(${value}) 与 target(${targetID}) 不一致`);
    }
  }
}

if (!pbxproj.includes("fileSystemSynchronizedGroups")) {
  problems.push("找不到 fileSystemSynchronizedGroups（Xcode 16 文件夹同步）");
}
if (!pbxproj.includes('INFOPLIST_FILE = Configuration/Info.plist;')) {
  problems.push("INFOPLIST_FILE 没有指向 Configuration/Info.plist");
}
if (!fs.existsSync(path.join(root, "Configuration", "Info.plist"))) {
  problems.push("缺少 Configuration/Info.plist");
}
if (!pbxproj.includes('INFOPLIST_FILE = Configuration/WidgetInfo.plist;')) {
  problems.push("widget target 的 INFOPLIST_FILE 没有指向 Configuration/WidgetInfo.plist");
}
if (!fs.existsSync(path.join(root, "Configuration", "WidgetInfo.plist"))) {
  problems.push("缺少 Configuration/WidgetInfo.plist");
}
if (!fs.existsSync(path.join(root, "Shared", "TranslationActivityAttributes.swift"))) {
  problems.push("缺少 Shared/TranslationActivityAttributes.swift（App 和扩展都要编译它）");
}

// 两个 target：App + 灵动岛扩展
const nativeTargets = [...pbxproj.matchAll(/isa = PBXNativeTarget;([\s\S]*?)\n\t\t\};/g)]
  .map((match) => match[1].match(/name = (\w+);/))
  .filter(Boolean)
  .map((match) => match[1]);
if (!nativeTargets.includes("EPUBTranslator")) problems.push("缺少 App target");
if (!nativeTargets.includes("EPUBTranslatorWidgets")) problems.push("缺少 EPUBTranslatorWidgets 扩展 target");
if (!pbxproj.includes('productType = "com.apple.product-type.app-extension";')) {
  problems.push("扩展 target 的 productType 不对");
}
if (!pbxproj.includes('dstSubfolderSpec = 13;')) {
  problems.push("App target 缺少 Embed App Extensions（dstSubfolderSpec 13）");
}
if (!pbxproj.includes("isa = PBXTargetDependency;")) {
  problems.push("App target 缺少对扩展的 target dependency");
}
const widgetBuildFiles = [...pbxproj.matchAll(/TranslationActivityAttributes\.swift in Sources/g)].length;
if (widgetBuildFiles < 2) {
  problems.push(`TranslationActivityAttributes.swift 只在 ${widgetBuildFiles} 个 Sources phase 里（应该 2 个：App + 扩展）`);
}

if (problems.length === 0) {
  console.log(
    `工程检查通过：${defined.size} 个对象，target = ${nativeTargets.join(", ")}，scheme ${scheme.length} 字节。`,
  );
} else {
  console.log(`工程检查发现 ${problems.length} 个问题：`);
  for (const problem of problems) console.log(`  - ${problem}`);
  process.exitCode = 1;
}
