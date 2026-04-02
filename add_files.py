import re
import uuid

def generate_id():
    return uuid.uuid4().hex[:24].upper()

files_to_add = [
    {"name": "BlurSettingsView.swift", "group_path": "Settings"},
    {"name": "BrowserExtensionSettingsView.swift", "group_path": "Settings"},
    {"name": "BlurContentView.swift", "group_path": "Components"},
    {"name": "BlurOverlayService.swift", "group_path": "Services"},
    {"name": "WindowTracker.swift", "group_path": "Services"},
    {"name": "BlurWindowManager.swift", "group_path": "Services"},
    {"name": "BlurredApp.swift", "group_path": "Models"},
]

with open('GhostVeil.xcodeproj/project.pbxproj', 'r') as f:
    pbxproj = f.read()

for f in files_to_add:
    file_id = generate_id()
    build_id = generate_id()

    # 1. Add PBXBuildFile
    build_file_str = f'\t\t{build_id} /* {f["name"]} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {f["name"]} */; }};\n'
    pbxproj = pbxproj.replace('/* End PBXBuildFile section */', build_file_str + '/* End PBXBuildFile section */')

    # 2. Add PBXFileReference
    file_ref_str = f'\t\t{file_id} /* {f["name"]} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f["name"]}; sourceTree = "<group>"; }};\n'
    pbxproj = pbxproj.replace('/* End PBXFileReference section */', file_ref_str + '/* End PBXFileReference section */')

    # 3. Add to PBXSourcesBuildPhase
    sources_phase_regex = re.compile(r'(/\* Sources \*/ = \{\n\s*isa = PBXSourcesBuildPhase;\n\s*buildActionMask = .*?;\n\s*files = \()')
    sources_match = sources_phase_regex.search(pbxproj)
    if sources_match:
        insertion = f'\n\t\t\t\t{build_id} /* {f["name"]} in Sources */,'
        pbxproj = pbxproj[:sources_match.end()] + insertion + pbxproj[sources_match.end():]

    # 4. Add to PBXGroup
    # Find the group by its path comment or path
    group_regex = re.compile(r'([0-9A-F]{24} /\* ' + f['group_path'] + r' \*/ = \{\n\s*isa = PBXGroup;\n\s*children = \()')
    group_match = group_regex.search(pbxproj)
    if group_match:
        insertion = f'\n\t\t\t\t{file_id} /* {f["name"]} */,'
        pbxproj = pbxproj[:group_match.end()] + insertion + pbxproj[group_match.end():]
    else:
        print(f"Could not find group {f['group_path']}")

with open('GhostVeil.xcodeproj/project.pbxproj', 'w') as f:
    f.write(pbxproj)

print("Updated project.pbxproj")
