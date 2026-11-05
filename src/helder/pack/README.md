# helder.pack

The packagers `helder build` uses for phones (src/helder/cli: Android.hx,
Ios.hx): pure functions from the program and the app's settings to the
bytes of the package, with no SDK, no Xcode and no Mac. Ported from hxmc
(MIT), then grown here.

- `Zip`, `Buf`, `Entropy`: a stored zip (and its reader), a byte buffer,
  the system's random source.
- `android`: the APK (`Apk`: AndroidManifest.xml in binary XML, `Axml`;
  resources.arsc, `Arsc`; classes.dex when the program needs it, `Dex`,
  `Glue`, `Classes`; 16 KB alignment; the v2 signature with the debug key,
  `DebugKey`, ECDSA P-256 in plain Haxe, `P256`, `Der`, or a release key,
  RSA or P-256 from PEM); the App Bundle (`Aab`: the manifest and
  resource table in aapt2's protobuf forms, `Pb`, after aapt2's
  Resources.proto and bundletool's config.proto, Apache-2.0; JAR signing
  with a PKCS#7 signature).
- `ios`: the bundle (`Bundle`: Info.plist, `_CodeSignature/CodeResources`
  with codesign's rules, the .ipa), property lists (`Plist`), the app
  icon's asset catalog (`AssetCatalog`).
- `apple`: what iOS and macOS share: the distribution code signature
  (`CodeSign`, `Identity`, `Rsa`), macOS's `.icns` (`Icns`).

## The asset catalog (a minimal actool)

`AssetCatalog.appIcon` writes the `Assets.car` Xcode's actool compiles
from an Xcode 15+ single-size app icon (one 1024 px image): the
renditions App Store validation asks for, iPhone's 60 pt at @2x and @3x
(120, 180 px), iPad's 76 and 83.5 pt at @2x (152, 167 px), the marketing
icon (1024 px, idiom ios-marketing), and a MultiSized rendition an idiom
listing its sizes; `Info.plist` names it (`CFBundleIcons` and
`~ipad`'s `CFBundlePrimaryIcon`: `CFBundleIconName` AppIcon,
`CFBundleIconFiles` the loose `AppIcon60x60@2x.png` and
`AppIcon76x76@2x~ipad.png` actool writes beside it).

The file is a BOM store (big-endian blocks, a block table, named
variables, B-trees of key and value blocks) holding CoreUI's blocks
(little-endian): `CARHEADER` (CoreUI 975, key semantics 2: keys with an
idiom), `EXTENDED_METADATA` (the deployment target, platform `ios`),
`KEYFORMAT` (appearance, localization, scale, idiom, subtype, size
index, identifier, element, part), `RENDITIONS` (each a CSI: size, scale,
`BGRA`, layout 12, the slices, metrics, blend, orientation and row TLVs,
the pixels in an uncompressed CELM: premultiplied, rows padded to 32
bytes), `FACETKEYS` (AppIcon to element 85, part 220 and its identifier,
actool's name hash), `APPEARANCEKEYS` (`UIAppearanceAny`) and
`BITMAPKEYS`. Uncompressed renditions are larger than actool's LZFSE or
deepmap2 (a 4 MB catalog) and CoreUI reads them at any deployment target.

`AssetCatalog.read` parses a catalog back. Not written: other assets
(image sets, colours), dark and tinted icons, compression.

## The code signature (a minimal codesign)

`CodeSign.sign` replaces the ad hoc signature hxmc's linker writes at the
end of an executable's `__LINKEDIT` with a distribution one, as `codesign`
signs an app bundle with an Apple Distribution certificate:

- the **CodeDirectory** (version 0x20400; 0x20500 with the hardened
  runtime flag, `runtime`, for macOS's Developer ID later): the bundle id,
  the team id, the SHA-256 of every 4 KB page up to the signature, and
  the special slots: Info.plist (1), the requirements (2), CodeResources
  (3), the entitlements (5), their DER form (7); the executable segment
  (`__TEXT`, main binary; unsigned pages allowed with `get-task-allow`);
- the **requirements**: the designated requirement codesign makes for
  the certificate: `identifier "<id>" and anchor apple generic and
  certificate leaf[subject.CN] = "<name>" and certificate
  1[field.1.2.840.113635.100.6.2.1] /* exists */` for an Apple
  Distribution or Development certificate, Developer ID's (its
  intermediate's and leaf's extensions, the team) for that one, and for
  any other `certificate root = H"<sha1>"` (the test CA's);
- the **entitlements** as XML and as CoreEntitlements' DER
  (`[APPLICATION 16] { INTEGER 1, [CONTEXT 16] { SEQUENCE { key, value }
  ... } }`, keys sorted), `CodeSign.entitlements`: the profile's
  `application-identifier` (its team prefix and the bundle id, the
  profile's may end in `*`), `com.apple.developer.team-identifier`,
  `get-task-allow` and `beta-reports-active` as the profile says,
  `keychain-access-groups`, and the app's file's keys (each one the
  profile grants);
- the **CMS signature** (RFC 5652 SignedData, detached, over the
  CodeDirectory): the chain's certificates, the signed attributes
  content type, signing time, message digest, Apple's
  1.2.840.113635.100.9.1 (a plist of the cdhashes: the CodeDirectory's
  SHA-256 truncated to 20 bytes) and .2 (the full SHA-256 with its
  algorithm), signed with RSA PKCS#1 v1.5 (`Rsa`: CRT, Montgomery's
  multiplication, plain Haxe) or ECDSA P-256 (`android.P256`).

The load commands follow: `LC_CODE_SIGNATURE`'s and `__LINKEDIT`'s sizes,
and `LC_BUILD_VERSION`'s SDK (helder.cli.Ios: the manifest's
`"sdk": {"version"}`, 26.0 by default). `Identity.fromPem` reads the
certificates (the signer is the one of the key; its chain the issuers
given) and the unencrypted private key (PKCS#8, PKCS#1, SEC 1), `Profile`
the provisioning profile's plist (its signature is Apple's to check:
the device's and App Store Connect's); `CodeSign.checkProfile` rejects a
profile without the certificate, expired or for another platform, and
warns for one with devices (not App Store's) or a chain that stops at the
leaf. No timestamp (App Store and TestFlight do not need one; notarisation
would); no fat binaries, nested code or frameworks.

## Verified where

- **Here, on Linux** (the test lane: `AssetCatalog.test.hx`,
  `CodeSign.test.hx`): the catalog parsed back (blocks, header, key
  format, a rendition a size with its pixels, the MultiSized ones, facet
  and bitmap keys, actool's name hash), the `.icns`; RSA's signature equal
  to openssl's, the identity and profile read, the entitlements merged and
  their DER, a stand-in Mach-O signed and parsed back (the load commands,
  the SuperBlob's slots, the CodeDirectory's fields, page hashes and
  special slots, the requirement, the CMS's attributes, its signature
  verified), a P-256 identity's too.
- **The pack lane** (`tests/pack/PackCheck.hx`): `helder build --target
  ios` of the pack project signed with an RSA identity (files' paths) and
  of Hello with a P-256 one (PEM text and the profile's base64 in the
  variables), both by `tests/pack/signing` (a throwaway CA, two leaves, a
  stand-in profile signed by the CA: for tests only): the bundle's files,
  CodeResources sealing them, the `DT*` keys, `PrivacyInfo.xcprivacy`,
  the signature's structure, the SDK, the DER entitlements, **`openssl cms
  -verify` of the CMS over the CodeDirectory** against the CA; the
  catalog against the structure of Apple's actool's
  (`tests/pack/reference/Assets.car`, from viraptor/actool's samples:
  blocks, key format, the icon's and the MultiSized rendition's TLVs,
  facet and bitmap keys).
- **CI, macOS** (`.github/workflows/ci.yml`'s ios-signing, not required:
  `tests/pack/signing/verify.sh`): the test CA trusted in the runner's
  keychain, the signed project's app checked by `codesign --verify --deep
  --strict -vvvv`, `codesign -d --entitlements :-`, `codesign -d -r-`, and
  its catalog by `xcrun assetutil --info`.
- **Not verified**: App Store Connect's acceptance. That takes the
  owner's account:
  1. an App ID for the bundle id and an app record in App Store Connect;
  2. an **Apple Distribution** certificate and its private key (Keychain's
     .p12, converted: `openssl pkcs12 -in d.p12 -nokeys -out d.pem`,
     `openssl pkcs12 -in d.p12 -nocerts -nodes -out d.key`, `-legacy` for
     an older .p12), with Apple's WWDR G3 intermediate appended to the PEM
     (`AppleWWDRCAG3.cer` from https://www.apple.com/certificateauthority/,
     `openssl x509 -inform DER`);
  3. an **App Store** provisioning profile for that App ID and certificate;
  4. an App Store Connect API key (its id, issuer id and .p8) for the
     upload;
  5. then `HELDER_IOS_CERTIFICATE=d.pem HELDER_IOS_KEY=d.key
     HELDER_IOS_PROFILE=AppStore.mobileprovision helder build --target ios
     --release`, and the upload: `xcrun altool --upload-app --type ios
     --file bin/ios/<name>.ipa --apiKey <key id> --apiIssuer <issuer id>`
     on a Mac, or Transporter (`iTMSTransporter -m upload -assetFile ...`)
     elsewhere. Its email or the build's TestFlight page says what the
     validation thinks (an ITMS-9xxxx code each); the build number
     (`"helder": {"build"}`) must rise with each upload.

## Credits

The formats as two projects document them, the code helder's own:
[viraptor/actool](https://github.com/viraptor/actool) (MIT: the CAR and
BOM layouts after Alexandre Colucci's
[reverse engineering](https://blog.timac.org/2018/1018-reverse-engineering-the-car-file-format/),
actool's name hash, iOS's rendition keys; its BOM writer's structure
followed in `AssetCatalog`; tests/pack/reference/Assets.car from its
samples) and [rcodesign](https://github.com/indygreg/apple-platform-rs)
(apple-codesign, MPL-2.0: the CodeDirectory, requirements, DER
entitlements and CMS attributes it describes; read for the format, no
code copied, so no MPL file is in helder), with Apple's own `cs_blobs.h`
and `requirement.h` (Security, open source).
