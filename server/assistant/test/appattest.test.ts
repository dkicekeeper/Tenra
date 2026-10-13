import { describe, expect, it } from "vitest";
import { AttestError, checkAssertion, fromBase64, issueChallenge, registerKey, toBase64, verifyAssertion, verifyAttestation } from "../src/appattest";
import { decodeCBOR } from "../src/cbor";
import { APPLE_APP_ATTESTATION_ROOT_PEM } from "../src/apple-root";
import { OID, parseCertificate, pemToDER } from "../src/der";
import { assertion, cbor } from "./attest-helpers";
import fixture from "./fixtures/appattest.json";
import { MemoryKV } from "./helpers";

// A synthetic attestation (test/fixtures/make-appattest.mjs): a test root instead of Apple's.

const sha256 = async (bytes: Uint8Array) => new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));

const now = new Date("2027-01-01T00:00:00Z");
const roots = [pemToDER(fixture.rootPem)];
const options = { appId: fixture.appId, roots, now };

function attestation(overrides: { authData?: Uint8Array; x5c?: Uint8Array[]; fmt?: string } = {}): string {
  return toBase64(
    cbor({
      fmt: overrides.fmt ?? "apple-appattest",
      attStmt: { x5c: overrides.x5c ?? [fromBase64(fixture.leaf), fromBase64(fixture.intermediate)], receipt: new Uint8Array([1, 2, 3]) },
      authData: overrides.authData ?? fromBase64(fixture.authData),
    }),
  );
}

const input = (extra: Partial<{ keyId: string; attestation: string; challenge: string }> = {}) => ({
  keyId: fixture.keyId,
  attestation: attestation(),
  challenge: fixture.challenge,
  ...extra,
});

async function reason(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
    return "accepted";
  } catch (error) {
    if (error instanceof AttestError) return error.reason;
    throw error;
  }
}

describe("CBOR", () => {
  it("decodes what the encoder wrote", () => {
    expect(decodeCBOR(cbor({ a: 1, b: "x", c: [2, new Uint8Array([9])] }))).toEqual({ a: 1, b: "x", c: [2, new Uint8Array([9])] });
  });

  it("refuses trailing and truncated input", () => {
    expect(() => decodeCBOR(Uint8Array.from([0x01, 0x02]))).toThrow();
    expect(() => decodeCBOR(Uint8Array.from([0x42, 0x01]))).toThrow();
  });
});

describe("Apple's root", () => {
  it("parses: P-384, valid until 2045", () => {
    const root = parseCertificate(pemToDER(APPLE_APP_ATTESTATION_ROOT_PEM));
    expect(root.curve).toBe(OID.p384);
    expect(root.signatureAlgorithm).toBe(OID.ecdsaSHA384);
    expect(root.notAfter.toISOString()).toBe("2045-03-15T00:00:00.000Z");
  });
});

describe("attestation", () => {
  it("accepts a valid attestation and returns the key", async () => {
    const stored = await verifyAttestation(input(), options);
    expect(stored.environment).toBe("development");
    expect(stored.counter).toBe(0);
    expect(await sha256(fromBase64(stored.publicKey))).toEqual(fromBase64(fixture.keyId));
  });

  it("refuses a chain that is not Apple's", async () => {
    expect(await reason(verifyAttestation(input(), { appId: fixture.appId, now }))).toBe("certificate_root");
  });

  it("refuses an expired or not yet valid chain", async () => {
    expect(await reason(verifyAttestation(input(), { ...options, now: new Date("2020-01-01T00:00:00Z") }))).toBe("certificate_expired");
  });

  it("refuses another challenge", async () => {
    expect(await reason(verifyAttestation(input({ challenge: "someone-else" }), options))).toBe("nonce");
  });

  it("refuses another app", async () => {
    expect(await reason(verifyAttestation(input(), { ...options, appId: "OTHERTEAM.com.example.other" }))).toBe("app_id");
  });

  it("refuses a key id that is not the certificate's", async () => {
    expect(await reason(verifyAttestation(input({ keyId: toBase64(new Uint8Array(32)) }), options))).toBe("key_id");
  });

  it("refuses authenticator data the nonce does not cover", async () => {
    const tampered = fromBase64(fixture.authData).slice();
    tampered[36] = 1; // counter
    expect(await reason(verifyAttestation(input({ attestation: attestation({ authData: tampered }) }), options))).toBe("nonce");
  });

  it("refuses a chain in the wrong order and other formats", async () => {
    const swapped = attestation({ x5c: [fromBase64(fixture.intermediate), fromBase64(fixture.leaf)] });
    expect(await reason(verifyAttestation(input({ attestation: swapped }), options))).not.toBe("accepted");
    expect(await reason(verifyAttestation(input({ attestation: attestation({ fmt: "packed" }) }), options))).toBe("format");
    expect(await reason(verifyAttestation(input({ attestation: "AAAA" }), options))).toBe("malformed");
  });
});

describe("registration", () => {
  it("needs a challenge this server issued, once", async () => {
    const kv = new MemoryKV();
    expect(await reason(registerKey(kv, input(), options))).toBe("challenge");

    await kv.put(`attest-challenge:${fixture.challenge}`, "1");
    await registerKey(kv, input(), options);
    expect(JSON.parse(kv.store.get(`attest-key:${fixture.keyId}`)!).environment).toBe("development");
    expect(await reason(registerKey(kv, input(), options))).toBe("challenge");
  });

  it("issues random challenges", async () => {
    const kv = new MemoryKV();
    const a = await issueChallenge(kv);
    const b = await issueChallenge(kv);
    expect(a).not.toBe(b);
    expect(a).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(kv.store.get(`attest-challenge:${a}`)).toBe("1");
  });
});

describe("assertion", () => {
  const body = new TextEncoder().encode('{"protocol":1,"messages":[]}');

  async function registered() {
    const kv = new MemoryKV();
    await kv.put(`attest-challenge:${fixture.challenge}`, "1");
    await registerKey(kv, input(), options);
    return kv;
  }

  it("accepts a signed body and records the counter", async () => {
    const kv = await registered();
    await checkAssertion(kv, fixture.keyId, await assertion(body, 1), body, fixture.appId);
    expect(JSON.parse(kv.store.get(`attest-key:${fixture.keyId}`)!).counter).toBe(1);
    await checkAssertion(kv, fixture.keyId, await assertion(body, 2), body, fixture.appId);
  });

  it("refuses a replayed request", async () => {
    const kv = await registered();
    const signed = await assertion(body, 1);
    await checkAssertion(kv, fixture.keyId, signed, body, fixture.appId);
    expect(await reason(checkAssertion(kv, fixture.keyId, signed, body, fixture.appId))).toBe("replay");
  });

  it("refuses another body, another app and an unknown key", async () => {
    const kv = await registered();
    const signed = await assertion(body, 1);
    const other = new TextEncoder().encode('{"protocol":1,"messages":[1]}');
    expect(await reason(checkAssertion(kv, fixture.keyId, signed, other, fixture.appId))).toBe("signature");
    expect(await reason(checkAssertion(kv, fixture.keyId, await assertion(body, 1, "OTHER.app"), body, fixture.appId))).toBe("app_id");
    expect(await reason(checkAssertion(kv, toBase64(new Uint8Array(32)), signed, body, fixture.appId))).toBe("unknown_key");
  });

  it("refuses a signature from another key", async () => {
    const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const point = new Uint8Array((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
    const stored = { publicKey: toBase64(point), counter: 0, environment: "production" as const };
    expect(await reason(verifyAssertion({ assertion: await assertion(body, 1), clientData: body }, stored, fixture.appId))).toBe("signature");
  });
});
