"""AndroidManifest.xml 에 Nearby Connections 권한을 넣는다.

사용법: python patch_manifest.py <AndroidManifest.xml 경로> <android_manifest_permissions.xml 경로>
이미 들어 있으면 아무것도 하지 않는다.
"""
import re
import sys

manifest_path, snippet_path = sys.argv[1], sys.argv[2]

with open(manifest_path, encoding="utf-8") as f:
    manifest = f.read()
with open(snippet_path, encoding="utf-8") as f:
    snippet = f.read()

snippet = re.sub(r"<!--.*?-->", "", snippet, flags=re.S).strip()

if "BLUETOOTH_ADVERTISE" in manifest:
    print("이미 권한이 들어 있음")
else:
    if "<application" not in manifest:
        sys.exit("<application 태그를 찾지 못함")
    manifest = manifest.replace("<application", snippet + "\n    <application", 1)
    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write(manifest)
    print("권한 추가 완료")
