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
import { spawn } from "node:child_process";
import { createHash, createPublicKey, verify } from "node:crypto";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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
    if (url.pathname.startsWith("/v1/")) {
      const t = jwt(auth.replace("Bearer ", ""), ecKey, "ES256");
      asc.jwt = t;
      if (!t.ok) return send(401, { errors: [{ detail: "bad token" }] });
      if (req.method === "GET" && url.pathname === "/v1/apps") {
        asc.bundleId = url.searchParams.get("filter[bundleId]");
        return send(200, { data: [{ type: "apps", id: "6400000001" }] });
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
      if (req.method === "GET" && url.pathname === "/v1/buildUploads/bu-1")
        return send(200, { data: { type: "buildUploads", id: "bu-1", attributes: { state: { state: "PROCESSING" } } } });
      return send(404, { errors: [{ detail: "no such route" }] });
    }
    if (auth !== "Bearer play-token") return send(401, { error: "bad token" });
    const m = url.pathname.match(/^(\/upload)?\/androidpublisher\/v3\/applications\/([^/]+)\/edits(?:\/([^/:]+))?(.*)$/);
    if (!m) return send(404, { error: "no such route" });
    play.pkg = m[2];
    const rest = m[4];
    if (req.method === "POST" && !m[3]) return send(200, { id: "edit-1" });
    if (req.method === "GET" && rest.startsWith("/tracks/")) return send(200, { track: rest.slice(8), releases: [{ status: "completed", versionCodes: ["1"] }] });
    if (req.method === "DELETE" && rest === "") { play.deleted = true; return send(204); }
    if (req.method === "POST" && m[1] && rest === "/bundles") {
      play.uploaded = body;
      return send(200, { versionCode: 2, sha256: createHash("sha256").update(body).digest("hex") });
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
const base = { ...process.env, HELDER_PLAY_API: `http://127.0.0.1:${port}`, HELDER_ASC_API: `http://127.0.0.1:${port}`,
  HELDER_ANDROID_SIGNING_CERTIFICATE: join(signing, "cert.pem"), HELDER_ANDROID_SIGNING_KEY: join(signing, "key.pem"),
  HELDER_IOS_CERTIFICATE: join(signing, "cert.pem"), HELDER_IOS_KEY: join(signing, "key.pem"), HELDER_IOS_PROFILE: join(signing, "test.mobileprovision") };
async function publish(args, env, want = 0) {
  const p = await new Promise((done) => {
    const c = spawn(helder, ["publish", "tests/pack/Hello.hx", ...args], { env, stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    c.stdout.on("data", (d) => (out += d));
    c.stderr.on("data", (d) => (out += d));
    c.on("close", (code) => done({ code, out }));
  });
  process.stdout.write(p.out);
  check(`helder publish ${args.join(" ")}: exit code ${want}`, p.code === want, `${p.code}`);
  return p.out;
}

// Google Play
const aab = join(dir, "Hello.aab");
const playEnv = { ...base, HELDER_PLAY_SERVICE_ACCOUNT: sa };
calls = [];
let out = await publish(["--play", "--dry-run", "-o", aab], playEnv);
check("dry run: the service account's RS256 JWT (its email, the androidpublisher scope, the token URI)", play.jwt?.ok
  && play.jwt.claims.iss === "publisher@helder-tests.iam.gserviceaccount.com" && play.jwt.claims.scope === "https://www.googleapis.com/auth/androidpublisher"
  && play.jwt.claims.aud === `http://127.0.0.1:${port}/token`);
check("dry run: edit opened, the track read, the edit deleted; nothing uploaded or committed", play.deleted && !play.uploaded && !play.committed
  && calls.some((c) => c.includes("/tracks/internal")), calls.join(", "));
check("dry run: what would change printed", out.includes("would") && out.includes("internal") && out.includes("versionCode"));
calls = []; play = {};
out = await publish(["--play", "--track", "beta", "-o", aab], playEnv);
check("the package's edit: org.helder.hello", play.pkg === "org.helder.hello");
check("bundles.upload: the .aab's bytes", play.uploaded && Buffer.compare(play.uploaded, readFileSync(aab)) === 0);
check("tracks.update: beta, the uploaded versionCode, completed", play.track?.track === "beta" && play.track.releases?.[0]?.versionCodes?.[0] === "2"
  && play.track.releases[0].status === "completed", JSON.stringify(play.track));
check("edits.commit", play.committed === true);
check("in order: insert, upload, track, commit", calls.join(",") === ["POST /token", "POST /androidpublisher/v3/applications/org.helder.hello/edits",
  "POST /upload/androidpublisher/v3/applications/org.helder.hello/edits/edit-1/bundles", "PUT /androidpublisher/v3/applications/org.helder.hello/edits/edit-1/tracks/beta",
  "POST /androidpublisher/v3/applications/org.helder.hello/edits/edit-1:commit"].join(","), calls.join(", "));

// TestFlight
const ipa = join(dir, "Hello.ipa");
const ascEnv = { ...base, HELDER_ASC_KEY_ID: "ABC123DEFG", HELDER_ASC_ISSUER_ID: "69a6de70-0000-47e3-e053-5b8c7c11a4d1",
  HELDER_ASC_KEY: readFileSync(join(signing, "key-ec.pem"), "utf8") };
calls = []; parts = {};
out = await publish(["--testflight", "--dry-run", "-o", ipa], ascEnv);
check("dry run: the API key's ES256 JWT (kid, issuer, audience)", asc.jwt?.ok && asc.jwt.header.kid === "ABC123DEFG"
  && asc.jwt.claims.iss === "69a6de70-0000-47e3-e053-5b8c7c11a4d1" && asc.jwt.claims.aud === "appstoreconnect-v1");
check("dry run: the app looked up by bundle id, nothing uploaded", asc.bundleId === "org.helder.Hello" && !calls.some((c) => c.startsWith("POST")), calls.join(", "));
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

// missing credentials
out = await publish(["--play", "-o", aab], { ...base, HELDER_PLAY_SERVICE_ACCOUNT: "" }, 1);
check("no service account: the message", out.includes("HELDER_PLAY_SERVICE_ACCOUNT"));
out = await publish(["--testflight", "-o", ipa], { ...base, HELDER_ASC_KEY_ID: "x" }, 1);
check("no App Store Connect key: the message", out.includes("HELDER_ASC_ISSUER_ID, HELDER_ASC_KEY not given"));
out = await publish(["-o", ipa], base, 2);
server.close();
if (failures > 0) { console.log(`publish: ${failures} failed`); process.exit(1); }
console.log("publish: ok");
