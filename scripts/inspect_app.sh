#!/usr/bin/env bash
# inspect_app.sh <Path.app|app.ipa>
# Dumps identity-relevant internals of an iOS app bundle.
set -euo pipefail
TARGET="$1"
TMP=$(mktemp -d /tmp/opencode/inspect.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

if [[ "$TARGET" == *.ipa ]]; then
  unzip -qo "$TARGET" -d "$TMP/x"
  APP=$(find "$TMP/x" -maxdepth 2 -name '*.app' | head -1)
else
  APP="$TARGET"
fi
echo "== App: $APP"
BIN=$(python3 - "$APP" <<'PY'
import plistlib,sys
print(plistlib.load(open(sys.argv[1]+"/Info.plist","rb"))["CFBundleExecutable"])
PY
)
python3 - "$APP" <<'PY'
import plistlib,sys
p=plistlib.load(open(sys.argv[1]+"/Info.plist","rb"))
for k in ("CFBundleIdentifier","CFBundleDisplayName","CFBundleShortVersionString","MinimumOSVersion"):
    print(f"{k} = {p.get(k)}")
for k,v in sorted(p.items()):
    if "Usage" in k: print(f"{k} = {v}")
PY

echo "== embedded.mobileprovision:"
if [[ -f "$APP/embedded.mobileprovision" ]]; then
  openssl smime -inform DER -verify -noverify -in "$APP/embedded.mobileprovision" -out "$TMP/plist.xml" 2>/dev/null ||
  cp "$APP/embedded.mobileprovision" "$TMP/plist.xml"
  python3 - "$TMP/plist.xml" <<'PY'
import plistlib,re,sys
raw=open(sys.argv[1],'rb').read()
m=re.search(rb'<\?xml.*</plist>',raw,re.S)
pl=plistlib.loads(m.group(0))
print("  Name:",pl.get("Name")); print("  TeamName:",pl.get("TeamName"),"TeamIdentifier:",pl.get("TeamIdentifier"))
print("  Created:",pl.get("CreationDate"),"Expires:",pl.get("ExpirationDate"))
print("  Entitlements dict:")
import json;print(json.dumps(pl.get("Entitlements",{}),indent=4,default=str))
PY
else
  echo "  ABSENT (no profile embedded)"
fi

echo "== embedded entitlements blob in binary:"
python3 - "$APP/$BIN" <<'PY'
import struct,re,sys
data=open(sys.argv[1],'rb').read()
i=data.find(b'\xfa\xde\x71\x71')
if i<0: print("  none"); raise SystemExit
ln=struct.unpack('>I',data[i+4:i+8])[0]
m=re.search(rb'<\?xml.*?</plist>',data[i:i+ln],re.S)
print(m.group(0).decode() if m else "(unparsable)")
j=data.find(b'\xfa\xde\x0c\xc0')
if j<0: j=data.find(b'\xfa\xde\x0c\x02')
if j>=0:
    ver,flags=struct.unpack('>II',data[j+8:j+16])
    print(f"CodeDirectory flags=0x{flags:x} ({'AD-HOC' if flags&2 else 'CERT-SIGNED'})")
k=data.find(b'\xfa\xde\x0b\x01')
print("CMS signature blob:", "present" if k>=0 else "absent")
PY
