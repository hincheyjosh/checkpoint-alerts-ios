#!/usr/bin/env python3
"""Generate ios/CheckpointAlerts.xcodeproj/project.pbxproj.

The project is hand-generated (no Mac here to run Xcode), so this script
is the source of truth for the project structure. Re-run it after adding
or removing source files, and commit the regenerated project.pbxproj.

Usage:
    python3 ios/Scripts/generate-project.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "CheckpointAlerts.xcodeproj", "project.pbxproj")

# (group path, [files]) — file paths are relative to ios/.
APP_SOURCES = [
    ("CheckpointAlerts", ["CheckpointAlertsApp.swift"]),
    ("CheckpointAlerts/Models", ["Checkpoint.swift", "TnCounties.swift"]),
    ("CheckpointAlerts/Data", [
        "TennesseeSource.swift", "CheckpointRepository.swift", "SettingsStore.swift",
    ]),
    ("CheckpointAlerts/Notifications", ["NotificationManager.swift"]),
    ("CheckpointAlerts/Background", ["BackgroundRefresh.swift"]),
    ("CheckpointAlerts/ViewModels", ["CheckpointViewModel.swift"]),
    ("CheckpointAlerts/Views", [
        "ContentView.swift", "HomeView.swift", "DetailView.swift",
        "SettingsView.swift", "FooterView.swift", "CannabisLeaf.swift",
    ]),
]
APP_RESOURCES = [
    ("CheckpointAlerts", ["Assets.xcassets"]),
]
APP_GROUP_ONLY = [
    ("CheckpointAlerts", ["Info.plist"]),
]

TEST_SOURCES = [
    ("CheckpointAlertsTests", ["TennesseeSourceTests.swift", "SelectionTests.swift"]),
]
TEST_RESOURCES = [
    ("CheckpointAlertsTests", ["thp-november-2026.txt"]),
]
TEST_GROUP_ONLY = [
    ("CheckpointAlertsTests", ["Info.plist"]),
]

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".xcassets": "folder.assetcatalog",
    ".plist": "text.plist.xml",
    ".txt": "text",
}


class Gen:
    def __init__(self):
        self.n = 0
        self.objs = {}  # id -> (comment, body lines)

    def nid(self):
        self.n += 1
        return "%024X" % self.n

    def add(self, comment, isa, fields):
        oid = self.nid()
        lines = [f"\t\t{oid} /* {comment} */ = {{isa = {isa};"]
        for k, v in fields:
            lines.append(f"\t\t\t{k} = {v};")
        lines.append("\t\t};")
        self.objs[oid] = "\n".join(lines)
        return oid


def plist_str(s):
    return f'"{s}"'


def plist_list(items):
    if not items:
        return "()"
    return "(\n" + "".join(f"\t\t\t\t{item},\n" for item in items) + "\t\t\t)"


def main():
    g = Gen()

    # --- file references -------------------------------------------------
    def fileref(group_path, filename):
        path = f"{group_path}/{filename}"
        ext = os.path.splitext(filename)[1]
        ftype = FILE_TYPES[ext]
        return g.add(
            filename, "PBXFileReference",
            [("lastKnownFileType", ftype), ("name", plist_str(filename)),
             ("path", plist_str(filename)), ("sourceTree", '"<group>"')],
        )

    def productref(name, ftype, path):
        return g.add(
            name, "PBXFileReference",
            [("explicitFileType", ftype), ("includeInIndex", "0"),
             ("path", plist_str(path)), ("sourceTree", "BUILT_PRODUCTS_DIR")],
        )

    app_product = productref("CheckpointAlerts.app", "wrapper.application", "CheckpointAlerts.app")
    test_product = productref("CheckpointAlertsTests.xctest", "wrapper.cfbundle", "CheckpointAlertsTests.xctest")

    # groups: name -> id, built bottom-up
    groups = {}

    def group(name, path, children, source_tree='"<group>"'):
        fields = [("children", plist_list(children))]
        if name:
            fields.append(("name", plist_str(name)))
        if path:
            fields.append(("path", plist_str(path)))
        fields.append(("sourceTree", source_tree))
        return g.add(name or "Project object", "PBXGroup", fields)

    def build_file(file_ref, comment):
        return g.add(comment, "PBXBuildFile", [("fileRef", file_ref)])

    # collect file refs per group path
    group_files = {}  # group path -> list of (filename, fileref id, phase)

    def register(group_path, filename, phase):
        ref = fileref(group_path, filename)
        group_files.setdefault(group_path, []).append((filename, ref, phase))
        return ref

    app_source_buildfiles = []
    for gp, files in APP_SOURCES:
        for f in files:
            ref = register(gp, f, "sources")
            app_source_buildfiles.append(build_file(ref, f"{f} in Sources"))
    app_resource_buildfiles = []
    for gp, files in APP_RESOURCES:
        for f in files:
            ref = register(gp, f, "resources")
            app_resource_buildfiles.append(build_file(ref, f"{f} in Resources"))
    for gp, files in APP_GROUP_ONLY:
        for f in files:
            register(gp, f, None)

    test_source_buildfiles = []
    for gp, files in TEST_SOURCES:
        for f in files:
            ref = register(gp, f, "sources")
            test_source_buildfiles.append(build_file(ref, f"{f} in Sources"))
    test_resource_buildfiles = []
    for gp, files in TEST_RESOURCES:
        for f in files:
            ref = register(gp, f, "resources")
            test_resource_buildfiles.append(build_file(ref, f"{f} in Resources"))
    for gp, files in TEST_GROUP_ONLY:
        for f in files:
            register(gp, f, None)

    # subgroups (leaf groups first)
    subgroup_ids = {}
    for gp in ["CheckpointAlerts/Models", "CheckpointAlerts/Data",
               "CheckpointAlerts/Notifications", "CheckpointAlerts/Background",
               "CheckpointAlerts/ViewModels", "CheckpointAlerts/Views"]:
        name = gp.split("/")[-1]
        children = [ref for (_, ref, _) in group_files.get(gp, [])]
        subgroup_ids[gp] = group(name, name, children)

    app_group_children = (
        [ref for (_, ref, _) in group_files.get("CheckpointAlerts", [])]
        + [subgroup_ids[gp] for gp in [
            "CheckpointAlerts/Models", "CheckpointAlerts/Data",
            "CheckpointAlerts/Notifications", "CheckpointAlerts/Background",
            "CheckpointAlerts/ViewModels", "CheckpointAlerts/Views"]]
    )
    app_group = group("CheckpointAlerts", "CheckpointAlerts", app_group_children)

    test_group = group(
        "CheckpointAlertsTests", "CheckpointAlertsTests",
        [ref for (_, ref, _) in group_files.get("CheckpointAlertsTests", [])])

    products_group = group("Products", "", [app_product, test_product], source_tree='"<group>"')
    frameworks_group = group("Frameworks", "", [], source_tree='"<group>"')
    main_group = group(
        "", "", [app_group, test_group, products_group, frameworks_group],
        source_tree='"<group>"')

    # --- build phases ----------------------------------------------------
    def phase(comment, isa, files):
        return g.add(comment, isa, [("buildActionMask", "2147483647"),
                                    ("files", plist_list(files)),
                                    ("runOnlyForDeploymentPostprocessing", "0")])

    app_sources_phase = phase("Sources", "PBXSourcesBuildPhase", app_source_buildfiles)
    app_frameworks_phase = phase("Frameworks", "PBXFrameworksBuildPhase", [])
    app_resources_phase = phase("Resources", "PBXResourcesBuildPhase", app_resource_buildfiles)
    test_sources_phase = phase("Sources", "PBXSourcesBuildPhase", test_source_buildfiles)
    test_frameworks_phase = phase("Frameworks", "PBXFrameworksBuildPhase", [])
    test_resources_phase = phase("Resources", "PBXResourcesBuildPhase", test_resource_buildfiles)

    # --- build configurations -------------------------------------------
    def settings(pairs):
        body = "{\n"
        for k, v in pairs:
            body += f"\t\t\t\t{k} = {v};\n"
        body += "\t\t\t}"
        return body

    def config(name, pairs):
        return g.add(name, "XCBuildConfiguration",
                     [("buildSettings", settings(pairs)), ("name", plist_str(name))])

    project_debug = config("Debug", [
        ("DEBUG_INFORMATION_FORMAT", "dwarf"),
        ("ENABLE_TESTABILITY", "YES"),
        ("GCC_C_LANGUAGE_STANDARD", "gnu17"),
        ("GCC_PREPROCESSOR_DEFINITIONS", '("DEBUG=1", "$(inherited)")'),
        ("IPHONEOS_DEPLOYMENT_TARGET", "16.0"),
        ("ONLY_ACTIVE_ARCH", "YES"),
        ("SDKROOT", "iphoneos"),
        ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG"),
        ("SWIFT_OPTIMIZATION_LEVEL", '"-Onone"'),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", '"1,2"'),
    ])
    project_release = config("Release", [
        ("DEBUG_INFORMATION_FORMAT", '"dwarf-with-dsym"'),
        ("ENABLE_NS_ASSERTIONS", "NO"),
        ("IPHONEOS_DEPLOYMENT_TARGET", "16.0"),
        ("MTL_ENABLE_DEBUG_INFO", "NO"),
        ("SDKROOT", "iphoneos"),
        ("SWIFT_COMPILATION_MODE", "wholemodule"),
        ("SWIFT_OPTIMIZATION_LEVEL", '"-O"'),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", '"1,2"'),
        ("VALIDATE_PRODUCT", "YES"),
    ])

    app_debug = config("Debug", [
        ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
        ("CODE_SIGN_STYLE", "Automatic"),
        ("CURRENT_PROJECT_VERSION", "1"),
        ("INFOPLIST_FILE", '"CheckpointAlerts/Info.plist"'),
        ("IPHONEOS_DEPLOYMENT_TARGET", "16.0"),
        ("LD_RUNPATH_SEARCH_PATHS", '("$(inherited)", "@executable_path/Frameworks")'),
        ("MARKETING_VERSION", "1.0"),
        ("PRODUCT_BUNDLE_IDENTIFIER", "com.checkpointalerts.app"),
        ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", '"1,2"'),
    ])
    app_release = config("Release", [
        ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
        ("CODE_SIGN_STYLE", "Automatic"),
        ("CURRENT_PROJECT_VERSION", "1"),
        ("INFOPLIST_FILE", '"CheckpointAlerts/Info.plist"'),
        ("IPHONEOS_DEPLOYMENT_TARGET", "16.0"),
        ("LD_RUNPATH_SEARCH_PATHS", '("$(inherited)", "@executable_path/Frameworks")'),
        ("MARKETING_VERSION", "1.0"),
        ("PRODUCT_BUNDLE_IDENTIFIER", "com.checkpointalerts.app"),
        ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", '"1,2"'),
    ])

    test_debug = config("Debug", [
        ("ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES", "YES"),
        ("BUNDLE_LOADER", '"$(TEST_HOST)"'),
        ("CODE_SIGN_STYLE", "Automatic"),
        ("CURRENT_PROJECT_VERSION", "1"),
        ("INFOPLIST_FILE", '"CheckpointAlertsTests/Info.plist"'),
        ("IPHONEOS_DEPLOYMENT_TARGET", "16.0"),
        ("LD_RUNPATH_SEARCH_PATHS", '("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks")'),
        ("MARKETING_VERSION", "1.0"),
        ("PRODUCT_BUNDLE_IDENTIFIER", "com.checkpointalerts.app.tests"),
        ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", '"1,2"'),
        ("TEST_HOST", '"$(BUILT_PRODUCTS_DIR)/CheckpointAlerts.app/CheckpointAlerts"'),
        ("WRAPPER_EXTENSION", "xctest"),
    ])
    test_release = config("Release", [
        ("ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES", "YES"),
        ("BUNDLE_LOADER", '"$(TEST_HOST)"'),
        ("CODE_SIGN_STYLE", "Automatic"),
        ("CURRENT_PROJECT_VERSION", "1"),
        ("INFOPLIST_FILE", '"CheckpointAlertsTests/Info.plist"'),
        ("IPHONEOS_DEPLOYMENT_TARGET", "16.0"),
        ("LD_RUNPATH_SEARCH_PATHS", '("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks")'),
        ("MARKETING_VERSION", "1.0"),
        ("PRODUCT_BUNDLE_IDENTIFIER", "com.checkpointalerts.app.tests"),
        ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", '"1,2"'),
        ("TEST_HOST", '"$(BUILT_PRODUCTS_DIR)/CheckpointAlerts.app/CheckpointAlerts"'),
        ("WRAPPER_EXTENSION", "xctest"),
    ])

    def config_list(name, debug_id, release_id):
        return g.add(name, "XCConfigurationList", [
            ("buildConfigurations", plist_list([debug_id, release_id])),
            ("defaultConfigurationIsVisible", "0"),
            ("defaultConfigurationName", "Release"),
        ])

    project_configs = config_list("Build configuration list for PBXProject \"CheckpointAlerts\"",
                                  project_debug, project_release)
    app_configs = config_list("Build configuration list for PBXNativeTarget \"CheckpointAlerts\"",
                              app_debug, app_release)
    test_configs = config_list("Build configuration list for PBXNativeTarget \"CheckpointAlertsTests\"",
                               test_debug, test_release)

    # --- targets ---------------------------------------------------------
    app_target = g.add("CheckpointAlerts", "PBXNativeTarget", [
        ("buildConfigurationList", app_configs),
        ("buildPhases", plist_list([app_sources_phase, app_frameworks_phase, app_resources_phase])),
        ("buildRules", "()"),
        ("dependencies", "()"),
        ("name", "CheckpointAlerts"),
        ("productName", "CheckpointAlerts"),
        ("productReference", app_product),
        ("productType", '"com.apple.product-type.application"'),
    ])

    proxy = g.add("PBXContainerItemProxy", "PBXContainerItemProxy", [
        ("containerPortal", "PROJECT_ID"),
        ("proxyType", "1"),
        ("remoteGlobalIDString", app_target),
        ("remoteInfo", "CheckpointAlerts"),
    ])
    dependency = g.add("PBXTargetDependency", "PBXTargetDependency", [
        ("target", app_target),
        ("targetProxy", proxy),
    ])

    test_target = g.add("CheckpointAlertsTests", "PBXNativeTarget", [
        ("buildConfigurationList", test_configs),
        ("buildPhases", plist_list([test_sources_phase, test_frameworks_phase, test_resources_phase])),
        ("buildRules", "()"),
        ("dependencies", plist_list([dependency])),
        ("name", "CheckpointAlertsTests"),
        ("productName", "CheckpointAlertsTests"),
        ("productReference", test_product),
        ("productType", '"com.apple.product-type.bundle.unit-test"'),
    ])

    # --- project ---------------------------------------------------------
    target_attrs = (
        "{\n"
        f"\t\t\t\t{app_target} = {{\n"
        "\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n"
        "\t\t\t\t};\n"
        f"\t\t\t\t{test_target} = {{\n"
        "\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n"
        f"\t\t\t\t\tTestTargetID = {app_target};\n"
        "\t\t\t\t};\n"
        "\t\t\t}"
    )
    project = g.add("CheckpointAlerts", "PBXProject", [
        ("attributes", "{\n"
         "\t\t\t\tLastUpgradeCheck = 1600;\n"
         f"\t\t\t\tTargetAttributes = {target_attrs};\n"
         "\t\t\t}"),
        ("buildConfigurationList", project_configs),
        ("compatibilityVersion", '"Xcode 14.0"'),
        ("developmentRegion", "en"),
        ("hasScannedForEncodings", "0"),
        ("knownRegions", "(\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t)"),
        ("mainGroup", main_group),
        ("productRefGroup", products_group),
        ("projectDirPath", '""'),
        ("projectRoot", '""'),
        ("targets", plist_list([app_target, test_target])),
    ])

    # fix the proxy's containerPortal to the real project id
    g.objs[proxy] = g.objs[proxy].replace("PROJECT_ID", project)

    # --- emit ------------------------------------------------------------
    out = []
    out.append("// !$*UTF8*$!")
    out.append("{")
    out.append("\tarchiveVersion = 1;")
    out.append("\tclasses = {")
    out.append("\t};")
    out.append("\tobjectVersion = 56;")
    out.append("\tobjects = {")
    for oid in sorted(g.objs):
        out.append(g.objs[oid])
    out.append("\t};")
    out.append(f"\trootObject = {project} /* CheckpointAlerts */;")
    out.append("}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"wrote {OUT} ({len(g.objs)} objects)")


if __name__ == "__main__":
    main()
