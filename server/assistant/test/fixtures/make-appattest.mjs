// Generates test/fixtures/appattest.json: a synthetic App Attest attestation with a test root,
// an intermediate and a leaf whose nonce extension is computed the way Apple's is. Real Apple
// attestations cannot be made off a device, so the tests trust this root instead.
//
//   node test/fixtures/make-appattest.mjs     (needs openssl)

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const dir = mkdtempSync(join(tmpdir(), "appattest-"));
const run = (...args) => execFileSync("openssl", args, { cwd: dir, stdio: ["ignore", "pipe", "pipe"] });
const sha256 = (bytes) => createHash("sha256").update(bytes).digest();

const appId = "TESTTEAM01.com.example.tenra";
const challenge = "test-challenge-0123456789";

// The leaf key, its point and the key id.
run("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "leaf.key");
const spki = run("ec", "-in", "leaf.key", "-pubout", "-outform", "DER");
const point = spki.subarray(spki.length - 65);
const keyId = sha256(point);

// Authenticator data: rpIdHash, flags, counter 0, aaguid, credential id, then a COSE key.
const cose = Buffer.from("a501020326200121582000000000000000000000000000000000000000000000000000000000000000002258200000000000000000000000000000000000000000000000000000000000000000", "hex");
const authData = Buffer.concat([
  sha256(Buffer.from(appId)),
  Buffer.from([0x40]),
  Buffer.from([0, 0, 0, 0]),
  Buffer.from("appattestdevelop"),
  Buffer.from([0x00, 0x20]),
  keyId,
  cose,
]);
const nonce = sha256(Buffer.concat([authData, sha256(Buffer.from(challenge))]));

// Root and intermediate on P-384, leaf on P-256 signed with SHA-256, like Apple's chain.
run("req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:secp384r1", "-nodes", "-keyout", "root.key", "-out", "root.pem",
  "-days", "9000", "-sha384", "-subj", "/CN=Test App Attestation Root CA/O=Tenra Tests");
writeFileSync(join(dir, "ca.ext"), "basicConstraints=critical,CA:true\nkeyUsage=critical,keyCertSign,cRLSign\n");
run("req", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:secp384r1", "-nodes", "-keyout", "int.key", "-out", "int.csr",
  "-subj", "/CN=Test App Attestation CA 1/O=Tenra Tests");
run("x509", "-req", "-in", "int.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial", "-out", "int.pem",
  "-days", "8000", "-sha384", "-extfile", "ca.ext");
writeFileSync(join(dir, "leaf.ext"), `1.2.840.113635.100.8.2=DER:3024a1220420${nonce.toString("hex")}\n`);
run("req", "-new", "-key", "leaf.key", "-out", "leaf.csr", "-subj", "/CN=" + keyId.toString("hex"));
run("x509", "-req", "-in", "leaf.csr", "-CA", "int.pem", "-CAkey", "int.key", "-CAcreateserial", "-out", "leaf.pem",
  "-days", "7000", "-sha256", "-extfile", "leaf.ext");

const der = (name) => run("x509", "-in", name, "-outform", "DER").toString("base64");
const pkcs8 = run("pkcs8", "-topk8", "-nocrypt", "-in", "leaf.key", "-outform", "DER").toString("base64");

const fixture = {
  appId,
  challenge,
  keyId: keyId.toString("base64"),
  rootPem: readFileSync(join(dir, "root.pem"), "utf8"),
  intermediate: der("int.pem"),
  leaf: der("leaf.pem"),
  authData: authData.toString("base64"),
  leafPrivateKey: pkcs8,
};
writeFileSync(new URL("./appattest.json", import.meta.url), JSON.stringify(fixture, null, 2) + "\n");
console.log("wrote appattest.json, key id", fixture.keyId);
