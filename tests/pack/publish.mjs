// helder publish against a stand-in of Google Play's and App Store Connect's
// APIs (the pack lane): node tests/pack/publish.mjs <helder> <dir>
//
// The stand-in checks what the real ones would: the service account's
// RS256 JWT (tests/pack/signing/key.pem's, its certificate's key) at the
// token endpoint, the bearer token on every call, Play's edit flow
// (edits.insert, bundles.upload of the very .aab, tracks.update,
// edits.commit; with --dry-run tracks.get and the edit deleted, nothing
// uploaded), the App Store Connect key's ES256 JWT (key-ec.pem as the .p8:
// its kid, issuer, audience), the app looked up by bundle id, Apple's
// build upload (buildUploads, buildUploadFiles, the parts PUT where the
// upload operations say, put together equal to the .ipa, the commit's
// MD5). Then the missing credentials' messages.
//
// helder setup: ios's certificate request (its RSA key's signature, checked
// here), the certificate made of it (issued as by Apple's WWDR G3, signed
// by key.pem), identity.pem (the certificate, G3, the key: they match), the
// App ID made, the app's record missing named, the profile made for that
// certificate, then a second run keeping all of it; android's upload key
// (a self-signed certificate node verifies, its fingerprints), the service
// account's edit opened and deleted, Google's 403s explained. No secret in
// the output. helder publish --listing --no-screenshot: the App Store's
// price (a price point found across pages) and availability made, then
// one territory patched, Play's data safety CSV sent.
import { spawn } from "node:child_process";
import { X509Certificate, createHash, createPrivateKey, createPublicKey, sign, verify } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { join, resolve } from "node:path";

const [helder, dir] = process.argv.slice(2);
rmSync(dir, { recursive: true, force: true });
mkdirSync(dir, { recursive: true });
const signing = resolve("tests/pack/signing");
const certKey = createPublicKey(readFileSync(join(signing, "cert.pem")));
const ecKey = createPublicKey(readFileSync(join(signing, "key-ec.pem")));
let failures = 0;
const check = (what, ok, detail = "") => {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}${detail ? "  " + detail : ""}`);
  if (!ok) failures++;
};
const b64url = (s) => Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64");
function jwt(token, key, alg) {
  const [h, c, s] = token.split(".");
  const header = JSON.parse(b64url(h)), claims = JSON.parse(b64url(c));
  const ok = alg === "RS256"
    ? verify("sha256", Buffer.from(`${h}.${c}`), key, b64url(s))
    : verify("sha256", Buffer.from(`${h}.${c}`), { key, dsaEncoding: "ieee-p1363" }, b64url(s));
  return { header, claims, ok };
}

let calls = [], parts = {}, play = {}, asc = {};
// (what App Store Connect keeps across runs: the certificates and profiles
// made, the price schedule and availability; flags for an App ID and an app not there yet)
const kept = { certs: [{ type: "certificates", id: "C-other", attributes: { name: "Someone else's", certificateContent: readFileSync(join(signing, "cert.pem"), "utf8").replace(/-----[^-]+-----|\s/g, "") } }],
  profiles: [], noBundle: false, noApp: false, price: null, availability: null };
// (DER, for the certificate made of a request)
const der = (tag, ...p) => {
  const body = Buffer.concat(p);
  const n = body.length, len = n < 0x80 ? [n] : n < 0x100 ? [0x81, n] : [0x82, n >> 8, n & 0xff];
  return Buffer.concat([Buffer.from([tag, ...len]), body]);
};
const seq = (...p) => der(0x30, ...p), set = (...p) => der(0x31, ...p);
const oid = (s) => {
  const p = s.split(".").map(Number), out = [40 * p[0] + p[1]];
  for (const v of p.slice(2)) { const b = [v & 0x7f]; let x = v >>> 7; while (x > 0) { b.unshift(0x80 | (x & 0x7f)); x >>>= 7; } out.push(...b); }
  return der(0x06, Buffer.from(out));
};
const utf8 = (s) => der(0x0c, Buffer.from(s));
const readDer = (b, at) => {
  let n = b[at + 1], start = at + 2;
  if (n & 0x80) { const k = n & 0x7f; n = 0; for (let i = 0; i < k; i++) n = n * 256 + b[at + 2 + i]; start += k; }
  return { at, start, end: start + n };
};
const kids = (b, node) => { const out = []; for (let at = node.start; at < node.end;) { const c = readDer(b, at); out.push(c); at = c.end; } return out; };
function certificateOf(csrContent) {
  const csr = Buffer.from(csrContent, "base64"), top = kids(csr, readDer(csr, 0)), info = kids(csr, top[0]);
  const spki = csr.subarray(info[2].at, info[2].end), key = createPublicKey({ key: spki, format: "der", type: "spki" });
  asc.csr = { ok: verify("sha256", csr.subarray(top[0].at, top[0].end), key, csr.subarray(top[2].start + 1, top[2].end)), bits: key.asymmetricKeyDetails.modulusLength };
  const g3 = seq(set(seq(oid("2.5.4.3"), utf8("Apple Worldwide Developer Relations Certification Authority"))), set(seq(oid("2.5.4.11"), utf8("G3"))),
    set(seq(oid("2.5.4.10"), utf8("Apple Inc."))), set(seq(oid("2.5.4.6"), der(0x13, Buffer.from("US")))));
  const subject = seq(set(seq(oid("2.5.4.3"), utf8("Apple Distribution: Helder Tests (TEAMID1234)"))), set(seq(oid("2.5.4.11"), utf8("TEAMID1234"))));
  const alg = seq(oid("1.2.840.113549.1.1.11"), Buffer.from([5, 0]));
  const time = (d) => der(0x17, Buffer.from(d.toISOString().replace(/[-:T]/g, "").slice(2, 14) + "Z"));
  const now = new Date();
  const tbs = seq(der(0xa0, der(0x02, Buffer.from([2]))), der(0x02, Buffer.from([0x11, 0x22, kept.certs.length])), alg, g3,
    seq(time(now), time(new Date(now.getTime() + 365 * 864e5))), subject, spki, der(0xa3, seq(seq(oid("1.2.840.113635.100.6.1.4"), der(0x04, Buffer.from([5, 0]))))));
  return seq(tbs, alg, der(0x03, Buffer.concat([Buffer.from([0]), sign("sha256", tbs, createPrivateKey(readFileSync(join(signing, "key.pem"))))])));
}
// (a profile: its property list alone, which is what helder reads of one)
const profileOf = (name, cert) => Buffer.from(`<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Name</key><string>${name}</string><key>TeamIdentifier</key><array><string>TEAMID1234</string></array>
<key>Entitlements</key><dict><key>application-identifier</key><string>TEAMID1234.org.helder.Hello</string></dict>
<key>DeveloperCertificates</key><array><data>${cert}</data></array><key>Platform</key><array><string>iOS</string></array></dict></plist>`);
const server = createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const body = Buffer.concat(chunks), url = new URL(req.url, "http://x");
    const send = (code, json) => {
      res.writeHead(code, { "Content-Type": "application/json" });
      res.end(json === undefined ? "" : JSON.stringify(json));
    };
    calls.push(`${req.method} ${url.pathname}`);
    if (url.pathname === "/token") {
      const form = new URLSearchParams(body.toString());
      const t = jwt(form.get("assertion"), certKey, "RS256");
      play.jwt = t;
      return send(t.ok && form.get("grant_type") === "urn:ietf:params:oauth:grant-type:jwt-bearer" ? 200 : 401, { access_token: "play-token" });
    }
    if (url.pathname.startsWith("/part/")) {
      parts[url.pathname] = body;
      return send(200);
    }
    const auth = req.headers.authorization ?? "";
    if (/^\/v[12]\//.test(url.pathname)) {
      const t = jwt(auth.replace("Bearer ", ""), ecKey, "ES256");
      asc.jwt = t;
      if (!t.ok) return send(401, { errors: [{ detail: "bad token" }] });
      if (req.method === "GET" && url.pathname === "/v1/bundleIds" && kept.noBundle) return send(200, { data: [] });
      if (req.method === "POST" && url.pathname === "/v1/bundleIds") {
        asc.bundleMade = JSON.parse(body).data.attributes;
        kept.noBundle = false;
        return send(201, { data: { type: "bundleIds", id: "B-1", attributes: asc.bundleMade } });
      }
      if (req.method === "GET" && url.pathname === "/v1/certificates") return send(200, { data: kept.certs });
      if (req.method === "POST" && url.pathname === "/v1/certificates") {
        const a = JSON.parse(body).data.attributes;
        asc.certificateType = a.certificateType;
        const c = { type: "certificates", id: `C-${kept.certs.length}`, attributes: { name: "Apple Distribution: Helder Tests", certificateType: a.certificateType,
          expirationDate: "2027-11-13T00:00:00.000+0000", certificateContent: certificateOf(a.csrContent).toString("base64") } };
        kept.certs.push(c);
        return send(201, { data: c });
      }
      if (req.method === "POST" && url.pathname === "/v1/profiles") {
        const d = JSON.parse(body).data;
        asc.profileMade = d;
        const cert = kept.certs.find((c) => c.id === d.relationships.certificates.data[0].id);
        const p = { type: "profiles", id: `P-${kept.profiles.length + 2}`, attributes: { name: d.attributes.name, profileType: d.attributes.profileType, profileState: "ACTIVE",
          profileContent: profileOf(d.attributes.name, cert.attributes.certificateContent).toString("base64") } };
        kept.profiles.push(p);
        return send(201, { data: p });
      }
      if (req.method === "GET" && url.pathname === "/v1/bundleIds") {
        asc.profileAsked = url.searchParams.get("filter[identifier]");
        return send(200, { data: [{ type: "bundleIds", id: "B-2", attributes: { identifier: "org.helder.Hello.extra" } },
          { type: "bundleIds", id: "B-1", attributes: { identifier: "org.helder.Hello" } }] });
      }
      if (req.method === "GET" && url.pathname === "/v1/bundleIds/B-1/profiles") {
        const content = readFileSync(join(signing, "test.mobileprovision")).toString("base64");
        return send(200, { data: [
          { type: "profiles", id: "P-dev", attributes: { profileType: "IOS_APP_DEVELOPMENT", profileState: "ACTIVE", profileContent: content } },
          { type: "profiles", id: "P-old", attributes: { profileType: "IOS_APP_STORE", profileState: "INVALID", profileContent: content } },
          { type: "profiles", id: "P-1", attributes: { profileType: "IOS_APP_STORE", profileState: "ACTIVE", profileContent: content } }, ...kept.profiles] });
      }
      if (req.method === "GET" && url.pathname === "/v1/apps") {
        asc.bundleId = url.searchParams.get("filter[bundleId]");
        return send(200, { data: kept.noApp ? [] : [{ type: "apps", id: "6400000001" }] });
      }
      // (the price and the territories)
      const territories = ["USA", "BEL", "NLD"];
      if (req.method === "GET" && url.pathname === "/v1/apps/6400000001/appInfos") return send(200, { data: [] });
      if (req.method === "GET" && url.pathname === "/v1/apps/6400000001/appPriceSchedule")
        return kept.price ? send(200, { data: { type: "appPriceSchedules", id: "6400000001" } }) : send(404, { errors: [{ status: "404" }] });
      if (req.method === "GET" && url.pathname === "/v1/appPriceSchedules/6400000001/baseTerritory") return send(200, { data: { type: "territories", id: kept.price.base } });
      if (req.method === "GET" && url.pathname === "/v1/appPriceSchedules/6400000001/manualPrices")
        return send(200, { data: [{ type: "appPrices", id: "ap-1", attributes: { startDate: null, endDate: null }, relationships: { appPricePoint: { data: { type: "appPricePoints", id: kept.price.point } } } }],
          included: [{ type: "appPricePoints", id: kept.price.point, attributes: { customerPrice: kept.price.point === "pp-free" ? "0.0" : "0.99" } }] });
      if (req.method === "GET" && url.pathname === "/v1/apps/6400000001/appPricePoints") {
        asc.pricePages = (asc.pricePages ?? 0) + 1;
        return url.searchParams.get("cursor") ? send(200, { data: [{ type: "appPricePoints", id: "pp-free", attributes: { customerPrice: "0.0" } }] })
          : send(200, { data: [{ type: "appPricePoints", id: "pp-099", attributes: { customerPrice: "0.99" } }], links: { next: `http://127.0.0.1:${port}${url.pathname}?filter%5Bterritory%5D=USA&cursor=2` } });
      }
      if (req.method === "POST" && url.pathname === "/v1/appPriceSchedules") {
        asc.priceSchedule = JSON.parse(body);
        kept.price = { base: asc.priceSchedule.data.relationships.baseTerritory.data.id, point: asc.priceSchedule.included[0].relationships.appPricePoint.data.id };
        return send(201, { data: { type: "appPriceSchedules", id: "6400000001" } });
      }
      if (req.method === "GET" && url.pathname === "/v1/territories") return send(200, { data: territories.map((id) => ({ type: "territories", id })) });
      if (req.method === "GET" && url.pathname === "/v1/apps/6400000001/appAvailabilityV2")
        return kept.availability ? send(200, { data: { type: "appAvailabilities", id: "av-1", attributes: { availableInNewTerritories: true } } }) : send(404, { errors: [{ status: "404" }] });
      if (req.method === "POST" && url.pathname === "/v2/appAvailabilities") {
        asc.availability = JSON.parse(body);
        kept.availability = Object.fromEntries(asc.availability.included.map((t) => [t.relationships.territory.data.id, t.attributes.available]));
        return send(201, { data: { type: "appAvailabilities", id: "av-1" } });
      }
      if (req.method === "GET" && url.pathname === "/v2/appAvailabilities/av-1/territoryAvailabilities")
        return send(200, { data: Object.entries(kept.availability).map(([t, available]) => ({ type: "territoryAvailabilities", id: `ta-${t}`, attributes: { available },
          relationships: { territory: { data: { type: "territories", id: t } } } })) });
      if (req.method === "PATCH" && url.pathname.startsWith("/v1/territoryAvailabilities/")) {
        asc.territoryPatched = [...(asc.territoryPatched ?? []), [url.pathname.slice(28), JSON.parse(body).data.attributes.available]];
        return send(200, { data: {} });
      }
      if (req.method === "POST" && url.pathname === "/v1/buildUploads") {
        asc.upload = JSON.parse(body);
        return send(201, { data: { type: "buildUploads", id: "bu-1" } });
      }
      if (req.method === "POST" && url.pathname === "/v1/buildUploadFiles") {
        asc.file = JSON.parse(body);
        const size = asc.file.data.attributes.fileSize, half = Math.ceil(size / 2);
        const op = (n, offset, length) => ({ method: "PUT", url: `http://127.0.0.1:${port}/part/${n}`, offset, length, partNumber: n + 1,
          requestHeaders: [{ name: "Content-Type", value: "application/octet-stream" }] });
        return send(201, { data: { type: "buildUploadFiles", id: "f-1", attributes: { uploadOperations: [op(0, 0, half), op(1, half, size - half)] } } });
      }
      if (req.method === "PATCH" && url.pathname === "/v1/buildUploadFiles/f-1") {
        asc.commit = JSON.parse(body);
        return send(200, { data: { type: "buildUploadFiles", id: "f-1" } });
      }
      // (the listing's screenshots)
      if (req.method === "GET" && url.pathname === "/v1/apps/6400000001/appStoreVersions") return send(200, { data: [{ type: "appStoreVersions", id: "v-1", attributes: { versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION" } }] });
      if (req.method === "GET" && url.pathname === "/v1/appStoreVersions/v-1/appStoreVersionLocalizations")
        return send(200, { data: [{ type: "appStoreVersionLocalizations", id: "loc-1", attributes: { locale: "en-US" } }] });
      if (req.method === "GET" && url.pathname === "/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets")
        return send(200, { data: [{ type: "appScreenshotSets", id: "set-67", attributes: { screenshotDisplayType: "APP_IPHONE_67" } }] });
      if (req.method === "GET" && url.pathname === "/v1/appScreenshotSets/set-67/appScreenshots")
        return send(200, { data: [{ type: "appScreenshots", id: "shot-old", attributes: { sourceFileChecksum: "0000" } }] });
      if (req.method === "DELETE" && url.pathname.startsWith("/v1/appScreenshots/")) { asc.deleted = [...(asc.deleted ?? []), url.pathname.slice(19)]; return send(204); }
      if (req.method === "POST" && url.pathname === "/v1/appScreenshotSets") {
        const t = JSON.parse(body).data.attributes.screenshotDisplayType;
        asc.sets = [...(asc.sets ?? []), t];
        return send(201, { data: { type: "appScreenshotSets", id: `set-${t}` } });
      }
      if (req.method === "POST" && url.pathname === "/v1/appScreenshots") {
        const a = JSON.parse(body).data, id = `shot-${(asc.shots ?? []).length}`;
        asc.shots = [...(asc.shots ?? []), { id, set: a.relationships.appScreenshotSet.data.id, name: a.attributes.fileName }];
        return send(201, { data: { type: "appScreenshots", id, attributes: { uploadOperations: [{ method: "PUT", url: `http://127.0.0.1:${port}/part/${id}`, offset: 0,
          length: a.attributes.fileSize, requestHeaders: [] }] } } });
      }
      if (req.method === "PATCH" && url.pathname.startsWith("/v1/appScreenshots/")) {
        asc.committed = { ...(asc.committed ?? {}), [url.pathname.slice(19)]: JSON.parse(body).data.attributes };
        return send(200, { data: {} });
      }
      if (req.method === "GET" && url.pathname === "/v1/buildUploads/bu-1")
        return send(200, { data: { type: "buildUploads", id: "bu-1", attributes: { state: { state: "PROCESSING" } } } });
      return send(404, { errors: [{ detail: "no such route" }] });
    }
    // (Google's refusals: a service account not invited, the API not enabled)
    if (auth === "Bearer forbidden") return send(403, { error: { code: 403, message: "The caller does not have permission", status: "PERMISSION_DENIED" } });
    if (auth === "Bearer disabled")
      return send(403, { error: { code: 403, message: "Google Play Android Developer API has not been used in project 123 before or it is disabled.", status: "PERMISSION_DENIED", details: [{ reason: "SERVICE_DISABLED" }] } });
    if (auth !== "Bearer play-token") return send(401, { error: "bad token" });
    const safety = url.pathname.match(/^\/androidpublisher\/v3\/applications\/([^/]+)\/dataSafety$/);
    if (req.method === "POST" && safety) { play.dataSafety = { pkg: safety[1], ...JSON.parse(body) }; return send(200, {}); }
    const m = url.pathname.match(/^(\/upload)?\/androidpublisher\/v3\/applications\/([^/]+)\/edits(?:\/([^/:]+))?(.*)$/);
    if (!m) return send(404, { error: "no such route" });
    play.pkg = m[2];
    const rest = m[4];
    if (req.method === "POST" && !m[3]) return send(200, { id: "edit-1" });
    if (req.method === "GET" && rest.startsWith("/tracks/")) return send(200, { track: rest.slice(8), releases: [{ status: "completed", versionCodes: ["1"] }] });
    if (req.method === "DELETE" && rest === "") { play.deleted = true; return send(204); }
    if (req.method === "GET" && rest === "/details") return send(200, { defaultLanguage: "en-US" });
    if (req.method === "GET" && rest === "/listings/en-US") return send(200, { language: "en-US", title: "Listed" });
    if (req.method === "POST" && m[1] && rest === "/bundles") {
      play.uploaded = body;
      return send(200, { versionCode: 2, sha256: createHash("sha256").update(body).digest("hex") });
    }
    // (each image type's: phoneScreenshots with an old one, the others none yet)
    const image = rest.match(/^\/listings\/en-US\/([A-Za-z]+)(?:\/([^/?]+))?/);
    if (req.method === "GET" && image && !image[2])
      return send(200, { images: image[1] === "phoneScreenshots" ? [{ id: "img-old", sha256: "00" }] : [] });
    if (req.method === "DELETE" && image?.[2]) { play.deletedImages = [...(play.deletedImages ?? []), image[2]]; return send(204); }
    if (req.method === "POST" && m[1] && image) {
      play.images = [...(play.images ?? []), body];
      return send(200, { image: { id: "img-new", sha256: createHash("sha256").update(body).digest("hex") } });
    }
    if (req.method === "PUT" && rest.startsWith("/tracks/")) { play.track = JSON.parse(body); return send(200, play.track); }
    if (req.method === "POST" && rest === ":commit") { play.committed = true; return send(200, { id: "edit-1" }); }
    return send(404, { error: "no such route" });
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;
const sa = join(dir, "service-account.json");
writeFileSync(sa, JSON.stringify({ type: "service_account", client_email: "publisher@helder-tests.iam.gserviceaccount.com",
  private_key: readFileSync(join(signing, "key.pem"), "utf8"), token_uri: `http://127.0.0.1:${port}/token` }));
// (one secret a target, as Expansion's release workflow has them: the
// identities as PEM bundles, the App Store Connect key as JSON, the profile
// fetched from App Store Connect, Google's access token)
const identity = readFileSync(join(signing, "cert.pem"), "utf8") + readFileSync(join(signing, "key.pem"), "utf8");
const base = { ...process.env, HELDER_PLAY_API: `http://127.0.0.1:${port}`, HELDER_ASC_API: `http://127.0.0.1:${port}`,
  HELDER_ANDROID_UPLOAD_IDENTITY: identity, HELDER_IOS_IDENTITY: identity };
async function publish(args, env, want = 0) {
  // (want null: any exit code)
  const p = await new Promise((done) => {
    const c = spawn(helder, ["publish", "tests/pack/Hello.hx", ...args], { env, stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    c.stdout.on("data", (d) => (out += d));
    c.stderr.on("data", (d) => (out += d));
    c.on("close", (code) => done({ code, out }));
  });
  process.stdout.write(p.out);
  if (want !== null) check(`helder publish ${args.join(" ")}: exit code ${want}`, p.code === want, `${p.code}`);
  return p.out;
}

// Google Play
const aab = join(dir, "Hello.aab");
const playEnv = { ...base, HELDER_PLAY_SERVICE_ACCOUNT: sa };
const tokenEnv = { ...base, GOOGLE_OAUTH_ACCESS_TOKEN: "play-token" };
calls = [];
let out = await publish(["--play", "--dry-run", "-o", aab], playEnv);
check("dry run: the service account's RS256 JWT (its email, the androidpublisher scope, the token URI)", play.jwt?.ok
  && play.jwt.claims.iss === "publisher@helder-tests.iam.gserviceaccount.com" && play.jwt.claims.scope === "https://www.googleapis.com/auth/androidpublisher"
  && play.jwt.claims.aud === `http://127.0.0.1:${port}/token`);
check("dry run: edit opened, the track read, the edit deleted; nothing uploaded or committed", play.deleted && !play.uploaded && !play.committed
  && calls.some((c) => c.includes("/tracks/internal")), calls.join(", "));
check("dry run: what would change printed", out.includes("would") && out.includes("internal") && out.includes("versionCode"));
calls = []; play = {};
out = await publish(["--play", "--track", "beta", "-o", aab], tokenEnv);
check("the package's edit: org.helder.hello", play.pkg === "org.helder.hello");
check("bundles.upload: the .aab's bytes", play.uploaded && Buffer.compare(play.uploaded, readFileSync(aab)) === 0);
check("tracks.update: beta, the uploaded versionCode, completed", play.track?.track === "beta" && play.track.releases?.[0]?.versionCodes?.[0] === "2"
  && play.track.releases[0].status === "completed", JSON.stringify(play.track));
check("edits.commit", play.committed === true);
check("an access token (Workload Identity Federation's): no token exchange; in order insert, upload, track, commit", calls.join(",") === ["POST /androidpublisher/v3/applications/org.helder.hello/edits",
  "POST /upload/androidpublisher/v3/applications/org.helder.hello/edits/edit-1/bundles", "PUT /androidpublisher/v3/applications/org.helder.hello/edits/edit-1/tracks/beta",
  "POST /androidpublisher/v3/applications/org.helder.hello/edits/edit-1:commit"].join(","), calls.join(", "));

// TestFlight
const ipa = join(dir, "Hello.ipa");
const ascEnv = { ...base, HELDER_ASC_API_KEY: JSON.stringify({ key_id: "ABC123DEFG", issuer_id: "69a6de70-0000-47e3-e053-5b8c7c11a4d1",
  private_key: readFileSync(join(signing, "key-ec.pem"), "utf8") }) };
calls = []; parts = {};
out = await publish(["--testflight", "--dry-run", "-o", ipa], ascEnv);
check("dry run: the API key's ES256 JWT (kid, issuer, audience)", asc.jwt?.ok && asc.jwt.header.kid === "ABC123DEFG"
  && asc.jwt.claims.iss === "69a6de70-0000-47e3-e053-5b8c7c11a4d1" && asc.jwt.claims.aud === "appstoreconnect-v1");
check("dry run: the app looked up by bundle id, nothing uploaded", asc.bundleId === "org.helder.Hello" && !calls.some((c) => c.startsWith("POST")), calls.join(", "));
check("the profile fetched: the App ID's active App Store one", asc.profileAsked === "org.helder.Hello" && calls.includes("GET /v1/bundleIds/B-1/profiles")
  && out.includes("from App Store Connect"));
calls = []; asc = {};
out = await publish(["--testflight", "-o", ipa], ascEnv);
const data = readFileSync(ipa);
check("buildUploads: the versions, iOS, the app", asc.upload?.data?.attributes?.cfBundleVersion === "1" && asc.upload.data.attributes.platform === "IOS"
  && asc.upload.data.relationships.app.data.id === "6400000001", JSON.stringify(asc.upload));
check("buildUploadFiles: the .ipa's name, size, com.apple.ipa", asc.file?.data?.attributes?.fileName === "Hello.ipa"
  && asc.file.data.attributes.fileSize === data.length && asc.file.data.attributes.uti === "com.apple.ipa" && asc.file.data.attributes.assetType === "ASSET");
check("the parts PUT where the operations say: the .ipa put together", Buffer.compare(Buffer.concat([parts["/part/0"] ?? Buffer.alloc(0),
  parts["/part/1"] ?? Buffer.alloc(0)]), data) === 0);
check("committed: uploaded, the file's MD5", asc.commit?.data?.attributes?.uploaded === true
  && asc.commit.data.attributes.sourceFileChecksums.file.hash === createHash("md5").update(data).digest("hex"));

// the store listings' screenshots (tests/story's store story rendered by
// helder publish --screenshots: a GPU, or Mesa's llvmpipe; skipped without
// one unless STORE_SHOTS_REQUIRE=1), then helder.run's from the stories
const both = { ...playEnv, ...ascEnv };
calls = []; play = {}; asc = {}; parts = {};
out = await publish(["--screenshots"], both, null);
if (out.includes("rendering failed") && process.env.STORE_SHOTS_REQUIRE !== "1") console.log("skip store screenshots (no GPU or llvmpipe here)");
else {
  check("--screenshots: rendered, the review sheet written", out.includes("rendered 4 screenshots") && existsSync("bin/store/review.html"));
  const shots = JSON.parse(readFileSync("bin/store/shots.json", "utf8"));
  const png = (f) => readFileSync(join("bin/store", f));
  check("each at its store size, opaque RGB (PNG colour type 2)", shots.filter((s) => s.type !== "icon").every((s) => { const b = png(s.file); return b.readUInt32BE(16) === s.width && b.readUInt32BE(20) === s.height && b[25] === 2; }),
    shots.map((s) => `${s.size} ${s.width}x${s.height}`).join(", "));
  calls = []; play = {}; asc = {};
  out = await publish(["--listing", "--dry-run"], both);
  check("listing dry run: the changes listed, nothing uploaded or deleted", out.includes("would") && out.includes("phoneScreenshots") && out.includes("APP_IPHONE_65")
    && !play.images && !play.deletedImages && !asc.shots && !asc.deleted && !asc.sets);
  check("listing dry run: the review sheet lists them", readFileSync("bin/store/review.html", "utf8").includes("What would change"));
  calls = []; play = {}; asc = {}; parts = {};
  out = await publish(["--listing"], both);
  const android = shots.filter((s) => s.store === "android"), ios = shots.filter((s) => s.store === "ios");
  check("Play: the old image deleted, ours uploaded (its bytes), committed", play.deletedImages?.join() === "img-old" && play.images?.length === android.length
    && Buffer.compare(play.images[0], png(android[0].file)) === 0 && play.committed === true);
  check("App Store: the old screenshot deleted, the missing sets made", asc.deleted?.join() === "shot-old" && asc.sets?.sort().join() === "APP_IPAD_PRO_3GEN_129,APP_IPHONE_65",
    `${asc.deleted} ${asc.sets}`);
  check("App Store: each screenshot reserved, sent, committed with its MD5", asc.shots?.length === ios.length && asc.shots.every((s, i) =>
    asc.committed?.[s.id]?.uploaded === true && asc.committed[s.id].sourceFileChecksum === createHash("md5").update(parts[`/part/${s.id}`] ?? "").digest("hex")
    && ios.some((x) => x.md5 === asc.committed[s.id].sourceFileChecksum)));
  // helder.run's screenshots: the same stories (examples/todo's store one), at a window's size, no caption band
  const run = await new Promise((done) => {
    const c = spawn(helder, ["share", "examples/todo", "--dry-run"], { env: base, stdio: ["ignore", "pipe", "pipe"] });
    let o = "";
    c.stdout.on("data", (d) => (o += d));
    c.stderr.on("data", (d) => (o += d));
    c.on("close", (code) => done({ code, out: o }));
  });
  process.stdout.write(run.out);
  const web = JSON.parse(readFileSync("bin/shots/run/shots.json", "utf8"));
  const shot = readFileSync(join("bin/shots/run", web[0]?.file ?? "shot-1.png"));
  check("--run: the store stories as helder.run's screenshots, 1280x800, opaque RGB, uncaptioned", run.code === 0 && run.out.includes("1 of the stories")
    && web.length === 1 && web[0].story === "Phone/Three items" && shot.readUInt32BE(16) === 1280 && shot.readUInt32BE(20) === 800 && shot[25] === 2,
    `${run.code} ${web.map((w) => w.story)}`);
}

// helder setup
async function helderRun(args, env, want = 0) {
  const p = await new Promise((done) => {
    const c = spawn(helder, args, { env, stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    c.stdout.on("data", (d) => (out += d));
    c.stderr.on("data", (d) => (out += d));
    c.on("close", (code) => done({ code, out }));
  });
  process.stdout.write(p.out);
  check(`helder ${args.join(" ")}: exit code ${want}`, p.code === want, `${p.code}`);
  return p.out;
}
// (a secret's body: a line from the middle of its base64)
const secretLine = (pem) => pem.split("\n").filter((l) => /^[A-Za-z0-9+/]{64}$/.test(l))[3];
const apple = resolve(dir, "keys", "apple");
calls = []; asc = {}; kept.noBundle = true; kept.noApp = true;
out = await helderRun(["setup", "ios", "tests/pack/Hello.hx", "-o", apple], ascEnv);
check("setup ios: the App ID made (identifier, the app's label, iOS)", asc.bundleMade?.identifier === "org.helder.Hello" && asc.bundleMade.platform === "IOS",
  JSON.stringify(asc.bundleMade));
check("setup ios: the app's record missing named, to be made by hand", out.includes("no app for org.helder.Hello") && out.includes("New App"));
kept.noApp = false;
check("setup ios: a distribution certificate requested: a 2048-bit RSA key's request, its signature good", asc.certificateType === "DISTRIBUTION"
  && asc.csr?.ok === true && asc.csr.bits === 2048, JSON.stringify(asc.csr));
const idPem = existsSync(join(apple, "identity.pem")) ? readFileSync(join(apple, "identity.pem"), "utf8") : "";
const idCerts = idPem.match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g) ?? [];
const made = kept.certs.at(-1);
check("identity.pem: App Store Connect's certificate, Apple's WWDR G3 after it, the key, which is the certificate's", idCerts.length === 2
  && new X509Certificate(idCerts[0]).raw.equals(Buffer.from(made.attributes.certificateContent, "base64"))
  && new X509Certificate(idCerts[1]).subject.includes("G3") && new X509Certificate(idCerts[0]).checkPrivateKey(createPrivateKey(idPem)));
check("setup ios: the App Store profile made for the bundle id and that certificate", asc.profileMade?.attributes?.profileType === "IOS_APP_STORE"
  && asc.profileMade.relationships.bundleId.data.id === "B-1" && asc.profileMade.relationships.certificates.data[0].id === made.id, JSON.stringify(asc.profileMade));
const keyJson = existsSync(join(apple, "asc-api-key.json")) ? JSON.parse(readFileSync(join(apple, "asc-api-key.json"), "utf8")) : {};
check("setup ios: the API key as one JSON (HELDER_ASC_API_KEY's)", keyJson.key_id === "ABC123DEFG" && keyJson.private_key?.includes("PRIVATE KEY"));
check("setup ios: the gh secret set lines, no secret in the output", out.includes(`gh secret set HELDER_IOS_IDENTITY < ${apple.replace(/\\/g, "/")}/identity.pem`)
  && out.includes("gh secret set HELDER_ASC_API_KEY <") && !out.includes(secretLine(idPem)) && !out.includes(secretLine(keyJson.private_key ?? "")));
calls = []; asc = {};
out = await helderRun(["setup", "ios", "tests/pack/Hello.hx", "-o", apple], ascEnv);
check("setup ios again: identity.pem kept, no certificate or profile made (the profile found)", out.includes("kept") && !calls.includes("POST /v1/certificates")
  && !calls.includes("POST /v1/profiles") && out.includes("from App Store Connect") && readFileSync(join(apple, "identity.pem"), "utf8") === idPem, calls.join(", "));
out = await helderRun(["setup", "ios", "tests/pack/Hello.hx", "-o", "tests/pack/keys"], ascEnv, 2);
check("setup: not into the project", out.includes("inside the project") && !existsSync("tests/pack/keys"));

const droid = resolve(dir, "keys", "android");
calls = []; play = {};
out = await helderRun(["setup", "android", "tests/pack/Hello.hx", "-o", droid], playEnv);
const upPem = existsSync(join(droid, "upload-identity.pem")) ? readFileSync(join(droid, "upload-identity.pem"), "utf8") : "";
const up = upPem ? new X509Certificate(upPem) : null;
check("setup android: the upload key, a self-signed 2048-bit certificate of it, 30 years", up && up.verify(up.publicKey) && up.checkPrivateKey(createPrivateKey(upPem))
  && up.publicKey.asymmetricKeyDetails.modulusLength === 2048 && new Date(up.validTo).getFullYear() - new Date(up.validFrom).getFullYear() === 30, up?.subject);
check("setup android: its SHA-1 and SHA-256 fingerprints", up && out.includes(up.fingerprint) && out.includes(up.fingerprint256));
check("setup android: the service account's edit opened and deleted", calls.includes("POST /androidpublisher/v3/applications/org.helder.hello/edits") && play.deleted === true,
  calls.join(", "));
check("setup android: the gh secret set lines, no secret in the output", out.includes("gh secret set HELDER_ANDROID_UPLOAD_IDENTITY <")
  && out.includes(`gh secret set HELDER_PLAY_SERVICE_ACCOUNT < ${sa.replace(/\\/g, "/")}`) && !out.includes(secretLine(upPem)));
out = await helderRun(["setup", "android", "tests/pack/Hello.hx", "-o", droid], { ...base, GOOGLE_OAUTH_ACCESS_TOKEN: "forbidden" }, 1);
check("setup android, the service account not invited: kept the key, what to do", out.includes("kept") && out.includes("Users and permissions")
  && readFileSync(join(droid, "upload-identity.pem"), "utf8") === upPem);
out = await helderRun(["setup", "android", "tests/pack/Hello.hx", "-o", droid], { ...base, GOOGLE_OAUTH_ACCESS_TOKEN: "disabled" }, 1);
check("setup android, the API not enabled: where to enable it", out.includes("enable the Google Play Android Developer API"));

// the listing's price, availability and data safety (no screenshots)
const app = join(dir, "listed");
mkdirSync(app, { recursive: true });
writeFileSync(join(app, "helder.json"), JSON.stringify({ name: "Listed", id: "org.helder.listed",
  listing: { appStore: { price: 0, availability: { territories: "all" } }, play: { dataSafety: "data-safety.csv" } } }));
writeFileSync(join(app, "Main.hx"), "class Main { static function main() {} }\n");
writeFileSync(join(app, "data-safety.csv"), "Question ID (machine readable),Response ID (machine readable),Response value,Answer requirement,Human-friendly question label\nPSL_DATA_COLLECTION_COLLECTS_PERSONAL_DATA,,false,REQUIRED,Does your app collect...\n");
const listed = (extra, env = both) => helderRun(["publish", app, "--listing", "--no-screenshot", ...extra], env);
calls = []; play = {}; asc = {};
out = await listed(["--dry-run"]);
check("listing dry run: the price, the availability and the data safety would be sent; nothing sent", out.includes("App Store price: free") && out.includes("3 territories")
  && out.includes("data safety") && !asc.priceSchedule && !asc.availability && !play.dataSafety);
calls = []; play = {}; asc = {};
out = await listed([]);
check("listing: free from the USA's price points (the second page's), the schedule made", asc.pricePages === 2
  && asc.priceSchedule?.data?.relationships?.baseTerritory?.data?.id === "USA" && asc.priceSchedule.included[0].relationships.appPricePoint.data.id === "pp-free",
  JSON.stringify(asc.priceSchedule));
check("listing: available in every territory, new ones too", asc.availability?.data?.attributes?.availableInNewTerritories === true
  && asc.availability.included.map((t) => t.relationships.territory.data.id).join() === "USA,BEL,NLD");
check("listing: Play's data safety, the CSV's text", play.dataSafety?.pkg === "org.helder.listed"
  && play.dataSafety.safetyLabels === readFileSync(join(app, "data-safety.csv"), "utf8"));
calls = []; asc = {};
kept.availability.BEL = false;
out = await listed([]);
check("listing again: the price as it is, nothing sent for it; the one territory that differs patched", !asc.priceSchedule && !asc.availability
  && JSON.stringify(asc.territoryPatched) === JSON.stringify([["ta-BEL", true]]), JSON.stringify(asc.territoryPatched));

// missing credentials
out = await publish(["--play", "-o", aab], { ...base, HELDER_PLAY_SERVICE_ACCOUNT: "" }, 1);
check("no service account: the message", out.includes("HELDER_PLAY_SERVICE_ACCOUNT"));
out = await publish(["--testflight", "-o", ipa], { ...base, HELDER_ASC_KEY_ID: "x" }, 1);
check("no App Store Connect key: the message", out.includes("HELDER_ASC_ISSUER_ID, HELDER_ASC_KEY not given"));
out = await publish(["--testflight", "-o", ipa], { ...ascEnv, HELDER_IOS_IDENTITY: readFileSync(join(signing, "key.pem"), "utf8") }, 1);
check("an identity without its certificate: the message", out.includes("no -----BEGIN CERTIFICATE----- block"));
out = await publish(["-o", ipa], base, 2);
server.close();
if (failures > 0) { console.log(`publish: ${failures} failed`); process.exit(1); }
console.log("publish: ok");
