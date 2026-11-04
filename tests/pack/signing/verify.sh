#!/bin/sh
# A signed app checked by Apple's own tools, on a Mac (CI's ios-signing job):
# the pack project built for an iPhone and signed by helder
# (helder.pack.apple.CodeSign) with this directory's throwaway identity
# (ca.pem: a test CA; cert.pem and key.pem: its RSA leaf; test.mobileprovision:
# a stand-in App Store profile the CA signed), the CA trusted in the system
# keychain (codesign checks the chain), then
#   codesign --verify --deep --strict -vvvv   the signature, the sealed files
#   codesign -d --entitlements :-             the entitlements as codesign reads them
#   codesign -d -r-                           the designated requirement
#   xcrun assetutil --info Assets.car         the icon's asset catalog (AssetCatalog)
#   plutil -lint                              Info.plist, PrivacyInfo.xcprivacy
# Usage: sh tests/pack/signing/verify.sh (from the repository's root, after
# bun install). App Store Connect's own validation is a TestFlight upload
# with the owner's account (src/helder/pack/README.md).
set -eu
out=bin/pack/signing
rm -rf "$out" bin/pack/project
mkdir -p "$out"
export PATH="$PWD/node_modules/.bin:$PATH"
node tests/pack/runtime.mjs bin/pack/rt
haxe -cp src -main helder.cli.Cli --custom-target hxmc=bin/cli/helder
cp -R tests/pack/project bin/pack/project
mkdir -p bin/pack/project/node_modules/helder
printf '{"name": "helder", "haxe": {"name": "helder", "classPath": "%s"}}' "$PWD/src" > bin/pack/project/node_modules/helder/package.json
HXMC_RT_DIR="$PWD/bin/pack/rt" HELDER_CACHE="$PWD/bin/pack/cache" \
  HELDER_IOS_CERTIFICATE=tests/pack/signing/cert.pem HELDER_IOS_KEY=tests/pack/signing/key.pem \
  HELDER_IOS_PROFILE=tests/pack/signing/test.mobileprovision \
  bin/cli/helder build bin/pack/project --target ios --release -o "$out/Packed.ipa"
(cd "$out" && unzip -q Packed.ipa)
app="$out/Payload/Packed.app"
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain tests/pack/signing/ca.pem
status=0
step() {
  echo "--- $*"
  "$@" || { echo "FAILED: $*"; status=1; }
}
step codesign --verify --deep --strict -vvvv "$app"
step codesign -d --entitlements :- "$app"
step codesign -d -r- "$app"
step codesign -dvvv "$app"
step xcrun assetutil --info "$app/Assets.car"
step plutil -lint "$app/Info.plist" "$app/PrivacyInfo.xcprivacy"
sudo security remove-trusted-cert -d tests/pack/signing/ca.pem || true
exit $status
