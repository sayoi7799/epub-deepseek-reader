// 一次性生成脚本：产出 EPUBTranslator.xcodeproj/project.pbxproj 与共享 scheme。
// 工程使用 Xcode 16 的 fileSystemSynchronizedGroups（文件夹自动同步），
// 所以新增 Swift 文件不需要改工程文件。之后请直接用 Xcode 维护。
//
// 两个 target：
//   EPUBTranslator        App（EPUBTranslator/ 自动同步）
//   EPUBTranslatorWidgets 灵动岛 / 锁屏 Live Activity 扩展（EPUBTranslatorWidgets/ 自动同步）
// 共享代码放在 Shared/，用传统的 group + build file 同时编进两个 target。
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(".");

function id(token) {
  return crypto.createHash("sha1").update(`epubtranslator:${token}`).digest("hex").slice(0, 24).toUpperCase();
}

const IDs = {
  project: id("project"),
  mainGroup: id("mainGroup"),
  productsGroup: id("productsGroup"),
  sharedGroup: id("sharedGroup"),
  configurationGroup: id("configurationGroup"),

  // App target
  target: id("target"),
  sourcesPhase: id("sourcesPhase"),
  frameworksPhase: id("frameworksPhase"),
  resourcesPhase: id("resourcesPhase"),
  embedPhase: id("embedPhase"),
  projectConfigList: id("projectConfigList"),
  targetConfigList: id("targetConfigList"),
  projectDebug: id("projectDebug"),
  projectRelease: id("projectRelease"),
  targetDebug: id("targetDebug"),
  targetRelease: id("targetRelease"),
  productRef: id("productRef"),
  sourcesGroup: id("sourcesGroup"),
  infoPlist: id("infoPlist"),

  // Widget extension target
  widgetTarget: id("widgetTarget"),
  widgetSourcesPhase: id("widgetSourcesPhase"),
  widgetFrameworksPhase: id("widgetFrameworksPhase"),
  widgetResourcesPhase: id("widgetResourcesPhase"),
  widgetConfigList: id("widgetConfigList"),
  widgetDebug: id("widgetDebug"),
  widgetRelease: id("widgetRelease"),
  widgetProductRef: id("widgetProductRef"),
  widgetSourcesGroup: id("widgetSourcesGroup"),
  widgetInfoPlist: id("widgetInfoPlist"),

  // 共享源码与嵌入关系
  sharedAttributesRef: id("sharedAttributesRef"),
  appSharedBuildFile: id("appSharedBuildFile"),
  widgetSharedBuildFile: id("widgetSharedBuildFile"),
  appexBuildFile: id("appexBuildFile"),
  widgetDependency: id("widgetDependency"),
  widgetProxy: id("widgetProxy"),
};

const bundleID = "com.epubtranslator.app";
const widgetBundleID = `${bundleID}.widgets`;

const commonProjectSettings = {
  ALWAYS_SEARCH_USER_PATHS: "NO",
  ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: "YES",
  CLANG_ANALYZER_NONNULL: "YES",
  CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION: "YES_AGGRESSIVE",
  CLANG_CXX_LANGUAGE_STANDARD: '"gnu++20"',
  CLANG_ENABLE_MODULES: "YES",
  CLANG_ENABLE_OBJC_ARC: "YES",
  CLANG_ENABLE_OBJC_WEAK: "YES",
  CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING: "YES",
  CLANG_WARN_BOOL_CONVERSION: "YES",
  CLANG_WARN_COMMA: "YES",
  CLANG_WARN_CONSTANT_CONVERSION: "YES",
  CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS: "YES",
  CLANG_WARN_DIRECT_OBJC_ISA_USAGE: "YES_ERROR",
  CLANG_WARN_DOCUMENTATION_COMMENTS: "YES",
  CLANG_WARN_EMPTY_BODY: "YES",
  CLANG_WARN_ENUM_CONVERSION: "YES",
  CLANG_WARN_INFINITE_RECURSION: "YES",
  CLANG_WARN_INT_CONVERSION: "YES",
  CLANG_WARN_NON_LITERAL_NULL_CONVERSION: "YES",
  CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF: "YES",
  CLANG_WARN_OBJC_LITERAL_CONVERSION: "YES",
  CLANG_WARN_OBJC_ROOT_CLASS: "YES_ERROR",
  CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER: "YES",
  CLANG_WARN_RANGE_LOOP_ANALYSIS: "YES",
  CLANG_WARN_STRICT_PROTOTYPES: "YES",
  CLANG_WARN_SUSPICIOUS_MOVE: "YES",
  CLANG_WARN_UNGUARDED_AVAILABILITY: "YES_AGGRESSIVE",
  CLANG_WARN_UNREACHABLE_CODE: "YES",
  CLANG_WARN__DUPLICATE_METHOD_MATCH: "YES",
  COPY_PHASE_STRIP: "NO",
  ENABLE_STRICT_OBJC_MSGSEND: "YES",
  ENABLE_USER_SCRIPT_SANDBOXING: "YES",
  GCC_C_LANGUAGE_STANDARD: "gnu17",
  GCC_NO_COMMON_BLOCKS: "YES",
  GCC_WARN_64_TO_32_BIT_CONVERSION: "YES",
  GCC_WARN_ABOUT_RETURN_TYPE: "YES_ERROR",
  GCC_WARN_UNDECLARED_SELECTOR: "YES",
  GCC_WARN_UNINITIALIZED_AUTOS: "YES_AGGRESSIVE",
  GCC_WARN_UNUSED_FUNCTION: "YES",
  GCC_WARN_UNUSED_VARIABLE: "YES",
  IPHONEOS_DEPLOYMENT_TARGET: "17.0",
  LOCALIZATION_PREFERS_STRING_CATALOGS: "YES",
  MTL_FAST_MATH: "YES",
  SDKROOT: "iphoneos",
};

const debugProjectSettings = {
  ...commonProjectSettings,
  DEBUG_INFORMATION_FORMAT: "dwarf",
  ENABLE_TESTABILITY: "YES",
  GCC_DYNAMIC_NO_PIC: "NO",
  GCC_OPTIMIZATION_LEVEL: "0",
  GCC_PREPROCESSOR_DEFINITIONS: '("DEBUG=1", "$(inherited)")',
  MTL_ENABLE_DEBUG_INFO: "INCLUDE_SOURCE",
  ONLY_ACTIVE_ARCH: "YES",
  SWIFT_ACTIVE_COMPILATION_CONDITIONS: '"DEBUG $(inherited)"',
  SWIFT_OPTIMIZATION_LEVEL: '"-Onone"',
};

const releaseProjectSettings = {
  ...commonProjectSettings,
  DEBUG_INFORMATION_FORMAT: '"dwarf-with-dsym"',
  ENABLE_NS_ASSERTIONS: "NO",
  MTL_ENABLE_DEBUG_INFO: "NO",
  SWIFT_COMPILATION_MODE: "wholemodule",
  SWIFT_OPTIMIZATION_LEVEL: '"-O"',
  VALIDATE_PRODUCT: "YES",
};

const appTargetSettings = {
  ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: "AccentColor",
  CODE_SIGN_STYLE: "Automatic",
  CURRENT_PROJECT_VERSION: "1",
  ENABLE_PREVIEWS: "YES",
  GENERATE_INFOPLIST_FILE: "NO",
  INFOPLIST_FILE: "Configuration/Info.plist",
  LD_RUNPATH_SEARCH_PATHS: '("$(inherited)", "@executable_path/Frameworks")',
  MARKETING_VERSION: "1.0",
  PRODUCT_BUNDLE_IDENTIFIER: bundleID,
  PRODUCT_NAME: '"$(TARGET_NAME)"',
  SWIFT_EMIT_LOC_STRINGS: "YES",
  SWIFT_STRICT_CONCURRENCY: "minimal",
  SWIFT_VERSION: "5.0",
  TARGETED_DEVICE_FAMILY: '"1,2"',
};

const widgetTargetSettings = {
  CODE_SIGN_STYLE: "Automatic",
  CURRENT_PROJECT_VERSION: "1",
  ENABLE_PREVIEWS: "YES",
  GENERATE_INFOPLIST_FILE: "NO",
  INFOPLIST_FILE: "Configuration/WidgetInfo.plist",
  LD_RUNPATH_SEARCH_PATHS: '("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks")',
  MARKETING_VERSION: "1.0",
  PRODUCT_BUNDLE_IDENTIFIER: widgetBundleID,
  PRODUCT_NAME: '"$(TARGET_NAME)"',
  SKIP_INSTALL: "YES",
  SWIFT_EMIT_LOC_STRINGS: "YES",
  SWIFT_STRICT_CONCURRENCY: "minimal",
  SWIFT_VERSION: "5.0",
  TARGETED_DEVICE_FAMILY: '"1,2"',
};

function settingsBlock(settings, indent = "\t\t\t\t") {
  return Object.keys(settings)
    .sort()
    .map((key) => `${indent}${key} = ${settings[key]};`)
    .join("\n");
}

const pbxproj = `// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
objects = {

/* Begin PBXBuildFile section */
		${IDs.appSharedBuildFile} /* TranslationActivityAttributes.swift in Sources (App) */ = {isa = PBXBuildFile; fileRef = ${IDs.sharedAttributesRef} /* TranslationActivityAttributes.swift */; };
		${IDs.widgetSharedBuildFile} /* TranslationActivityAttributes.swift in Sources (Widgets) */ = {isa = PBXBuildFile; fileRef = ${IDs.sharedAttributesRef} /* TranslationActivityAttributes.swift */; };
		${IDs.appexBuildFile} /* EPUBTranslatorWidgets.appex in Embed App Extensions */ = {isa = PBXBuildFile; fileRef = ${IDs.widgetProductRef} /* EPUBTranslatorWidgets.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		${IDs.widgetProxy} /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = ${IDs.project} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = ${IDs.widgetTarget};
			remoteInfo = EPUBTranslatorWidgets;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		${IDs.embedPhase} /* Embed App Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				${IDs.appexBuildFile} /* EPUBTranslatorWidgets.appex in Embed App Extensions */,
			);
			name = "Embed App Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		${IDs.infoPlist} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		${IDs.widgetInfoPlist} /* WidgetInfo.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = WidgetInfo.plist; sourceTree = "<group>"; };
		${IDs.sharedAttributesRef} /* TranslationActivityAttributes.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TranslationActivityAttributes.swift; sourceTree = "<group>"; };
		${IDs.productRef} /* EPUBTranslator.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = EPUBTranslator.app; sourceTree = BUILT_PRODUCTS_DIR; };
		${IDs.widgetProductRef} /* EPUBTranslatorWidgets.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = EPUBTranslatorWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		${IDs.sourcesGroup} /* EPUBTranslator */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = EPUBTranslator;
			sourceTree = "<group>";
		};
		${IDs.widgetSourcesGroup} /* EPUBTranslatorWidgets */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = EPUBTranslatorWidgets;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		${IDs.frameworksPhase} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${IDs.widgetFrameworksPhase} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		${IDs.mainGroup} = {
			isa = PBXGroup;
			children = (
				${IDs.sourcesGroup} /* EPUBTranslator */,
				${IDs.widgetSourcesGroup} /* EPUBTranslatorWidgets */,
				${IDs.sharedGroup} /* Shared */,
				${IDs.configurationGroup} /* Configuration */,
				${IDs.productsGroup} /* Products */,
			);
			sourceTree = "<group>";
		};
		${IDs.sharedGroup} /* Shared */ = {
			isa = PBXGroup;
			children = (
				${IDs.sharedAttributesRef} /* TranslationActivityAttributes.swift */,
			);
			path = Shared;
			sourceTree = "<group>";
		};
		${IDs.productsGroup} /* Products */ = {
			isa = PBXGroup;
			children = (
				${IDs.productRef} /* EPUBTranslator.app */,
				${IDs.widgetProductRef} /* EPUBTranslatorWidgets.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		${IDs.configurationGroup} /* Configuration */ = {
			isa = PBXGroup;
			children = (
				${IDs.infoPlist} /* Info.plist */,
				${IDs.widgetInfoPlist} /* WidgetInfo.plist */,
			);
			path = Configuration;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		${IDs.target} /* EPUBTranslator */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${IDs.targetConfigList} /* Build configuration list for PBXNativeTarget "EPUBTranslator" */;
			buildPhases = (
				${IDs.sourcesPhase} /* Sources */,
				${IDs.frameworksPhase} /* Frameworks */,
				${IDs.resourcesPhase} /* Resources */,
				${IDs.embedPhase} /* Embed App Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				${IDs.widgetDependency} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				${IDs.sourcesGroup} /* EPUBTranslator */,
			);
			name = EPUBTranslator;
			packageProductDependencies = (
			);
			productName = EPUBTranslator;
			productReference = ${IDs.productRef} /* EPUBTranslator.app */;
			productType = "com.apple.product-type.application";
		};
		${IDs.widgetTarget} /* EPUBTranslatorWidgets */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${IDs.widgetConfigList} /* Build configuration list for PBXNativeTarget "EPUBTranslatorWidgets" */;
			buildPhases = (
				${IDs.widgetSourcesPhase} /* Sources */,
				${IDs.widgetFrameworksPhase} /* Frameworks */,
				${IDs.widgetResourcesPhase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				${IDs.widgetSourcesGroup} /* EPUBTranslatorWidgets */,
			);
			name = EPUBTranslatorWidgets;
			packageProductDependencies = (
			);
			productName = EPUBTranslatorWidgets;
			productReference = ${IDs.widgetProductRef} /* EPUBTranslatorWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		${IDs.project} /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {
					${IDs.target} = {
						CreatedOnToolsVersion = 16.0;
					};
					${IDs.widgetTarget} = {
						CreatedOnToolsVersion = 16.0;
					};
				};
			};
			buildConfigurationList = ${IDs.projectConfigList} /* Build configuration list for PBXProject "EPUBTranslator" */;
			developmentRegion = "zh-Hans";
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				"zh-Hans",
			);
			mainGroup = ${IDs.mainGroup};
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = ${IDs.productsGroup} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				${IDs.target} /* EPUBTranslator */,
				${IDs.widgetTarget} /* EPUBTranslatorWidgets */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		${IDs.resourcesPhase} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${IDs.widgetResourcesPhase} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		${IDs.sourcesPhase} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${IDs.appSharedBuildFile} /* TranslationActivityAttributes.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${IDs.widgetSourcesPhase} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${IDs.widgetSharedBuildFile} /* TranslationActivityAttributes.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		${IDs.widgetDependency} /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = ${IDs.widgetTarget} /* EPUBTranslatorWidgets */;
			targetProxy = ${IDs.widgetProxy} /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		${IDs.projectDebug} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
${settingsBlock(debugProjectSettings)}
			};
			name = Debug;
		};
		${IDs.projectRelease} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
${settingsBlock(releaseProjectSettings)}
			};
			name = Release;
		};
		${IDs.targetDebug} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
${settingsBlock(appTargetSettings)}
			};
			name = Debug;
		};
		${IDs.targetRelease} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
${settingsBlock(appTargetSettings)}
			};
			name = Release;
		};
		${IDs.widgetDebug} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
${settingsBlock(widgetTargetSettings)}
			};
			name = Debug;
		};
		${IDs.widgetRelease} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
${settingsBlock(widgetTargetSettings)}
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		${IDs.projectConfigList} /* Build configuration list for PBXProject "EPUBTranslator" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${IDs.projectDebug} /* Debug */,
				${IDs.projectRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		${IDs.targetConfigList} /* Build configuration list for PBXNativeTarget "EPUBTranslator" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${IDs.targetDebug} /* Debug */,
				${IDs.targetRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		${IDs.widgetConfigList} /* Build configuration list for PBXNativeTarget "EPUBTranslatorWidgets" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${IDs.widgetDebug} /* Debug */,
				${IDs.widgetRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = ${IDs.project} /* Project object */;
}
`;

const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "${IDs.target}"
               BuildableName = "EPUBTranslator.app"
               BlueprintName = "EPUBTranslator"
               ReferencedContainer = "container:EPUBTranslator.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "${IDs.target}"
            BuildableName = "EPUBTranslator.app"
            BlueprintName = "EPUBTranslator"
            ReferencedContainer = "container:EPUBTranslator.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "${IDs.target}"
            BuildableName = "EPUBTranslator.app"
            BlueprintName = "EPUBTranslator"
            ReferencedContainer = "container:EPUBTranslator.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
`;

const projectDir = path.join(root, "EPUBTranslator.xcodeproj");
fs.mkdirSync(path.join(projectDir, "xcshareddata", "xcschemes"), { recursive: true });
fs.writeFileSync(path.join(projectDir, "project.pbxproj"), pbxproj, "utf8");
fs.writeFileSync(path.join(projectDir, "xcshareddata", "xcschemes", "EPUBTranslator.xcscheme"), scheme, "utf8");

console.log("已生成 EPUBTranslator.xcodeproj");
for (const [key, value] of Object.entries(IDs)) {
  console.log(`  ${key}: ${value}`);
}
