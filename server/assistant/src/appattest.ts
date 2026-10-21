import { APPLE_APP_ATTESTATION_ROOT_PEM } from "./apple-root";
import { CBORError, decodeCBOR, type CBORValue } from "./cbor";
import { children, DERError, ecdsaRaw, equalBytes, OID, parseCertificate, pemToDER, readTLV, type Certificate } from "./der";
import type { KVLike } from "./quota";

// App Attest (Apple's DeviceCheck): proof that a request comes from the real Tenra app on a
// real Apple device. It is what lets people without Pro use the cloud brain: their quota is
// counted per attested key, which a script cannot mint (docs/domains/assistant.md §8, §11).
//
//   GET  /v1/attest/challenge            → {challenge}       one-time, 5 minutes
//   POST /v1/attest {keyId, attestation, challenge}          once per install
//   POST /v1/turn   x-tenra-key, x-tenra-assertion           every request
//
// The attestation is checked as Apple describes ("Validating apps that connect to your
// server"): the certificate chain up to the App Attestation root, the nonce in the leaf
// certificate, the key id, the app id, a zero counter, the environment and the credential id.
// An assertion signs the request body; its counter must grow, so a copied request is refused.

export class AttestError extends Error {
  constructor(readonly reason: string) {
    super(reason);
  }
}

export interface StoredKey {
  /** The key's raw public point, base64. */
  publicKey: string;
  counter: number;
  environment: "production" | "development";
}

export interface AttestOptions {
  /** TEAMID.bundle-id */
  appId: string;
  /** Trust anchors (DER); Apple's App Attestation root by default. */
  roots?: Uint8Array[];
  now?: Date;
}

const CHALLENGE_TTL = 300;
const KEY_TTL = 400 * 24 * 3600;
const encoder = new TextEncoder();
const AAGUID_PRODUCTION = new Uint8Array([...encoder.encode("appattest"), 0, 0, 0, 0, 0, 0, 0]);
const AAGUID_DEVELOPMENT = encoder.encode("appattestdevelop");

// MARK: - Bytes

export function fromBase64(text: string): Uint8Array {
  const standard = text.replace(/-/g, "+").replace(/_/g, "/");
  const padded = standard + "=".repeat((4 - (standard.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

const concat = (a: Uint8Array, b: Uint8Array) => {
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
};

const sha256 = async (bytes: Uint8Array) => new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));

const field = (value: CBORValue | undefined, name: string): Uint8Array => {
  if (!(value instanceof Uint8Array)) throw new AttestError(`missing_${name}`);
  return value;
};

// MARK: - Authenticator data

interface AuthenticatorData {
  rpIdHash: Uint8Array;
  counter: number;
  aaguid?: Uint8Array;
  credentialId?: Uint8Array;
}

function parseAuthenticatorData(bytes: Uint8Array, attested: boolean): AuthenticatorData {
  if (bytes.length < 37) throw new AttestError("auth_data");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const data: AuthenticatorData = { rpIdHash: bytes.subarray(0, 32), counter: view.getUint32(33) };
  if (attested) {
    if (bytes.length < 55) throw new AttestError("auth_data");
    const length = view.getUint16(53);
    if (bytes.length < 55 + length) throw new AttestError("auth_data");
    data.aaguid = bytes.subarray(37, 53);
    data.credentialId = bytes.subarray(55, 55 + length);
  }
  return data;
}

// MARK: - Certificates

const CURVES: Record<string, { name: string; size: number }> = {
  [OID.p256]: { name: "P-256", size: 32 },
  [OID.p384]: { name: "P-384", size: 48 },
};

const HASHES: Record<string, string> = {
  [OID.ecdsaSHA256]: "SHA-256",
  [OID.ecdsaSHA384]: "SHA-384",
};

async function signedBy(child: Certificate, issuer: Certificate): Promise<boolean> {
  const curve = CURVES[issuer.curve];
  const hash = HASHES[child.signatureAlgorithm];
  if (!curve || !hash || !equalBytes(child.issuer, issuer.subject)) return false;
  const key = await crypto.subtle.importKey("spki", issuer.spki, { name: "ECDSA", namedCurve: curve.name }, false, ["verify"]);
  return crypto.subtle.verify({ name: "ECDSA", hash }, key, ecdsaRaw(child.signature, curve.size), child.tbs);
}

const current = (certificate: Certificate, now: Date) => certificate.notBefore <= now && now <= certificate.notAfter;

async function verifyChain(leaf: Certificate, intermediate: Certificate, roots: Certificate[], now: Date): Promise<void> {
  if (!current(leaf, now) || !current(intermediate, now)) throw new AttestError("certificate_expired");
  if (!(await signedBy(leaf, intermediate))) throw new AttestError("certificate_chain");
  for (const root of roots) {
    if (current(root, now) && (await signedBy(intermediate, root))) return;
  }
  throw new AttestError("certificate_root");
}

/** The nonce in the leaf certificate: SEQUENCE { [1] EXPLICIT OCTET STRING }. */
function certificateNonce(leaf: Certificate): Uint8Array {
  const value = leaf.extensions.get(OID.appAttestNonce);
  if (!value) throw new AttestError("nonce_missing");
  const { tlv: sequence } = readTLV(value);
  for (const item of children(sequence)) {
    if (item.tag !== 0xa1) continue;
    const [octets] = children(item);
    if (octets?.tag === 0x04) return octets.value;
  }
  throw new AttestError("nonce_missing");
}

// MARK: - Attestation

export async function verifyAttestation(
  input: { keyId: string; attestation: string; challenge: string },
  options: AttestOptions,
): Promise<StoredKey> {
  try {
    const object = decodeCBOR(fromBase64(input.attestation));
    if (typeof object !== "object" || object === null || Array.isArray(object) || object instanceof Uint8Array) {
      throw new AttestError("format");
    }
    if (object.fmt !== "apple-appattest") throw new AttestError("format");
    const statement = object.attStmt;
    if (typeof statement !== "object" || statement === null || Array.isArray(statement) || statement instanceof Uint8Array) {
      throw new AttestError("format");
    }
    const x5c = statement.x5c;
    if (!Array.isArray(x5c) || x5c.length < 2) throw new AttestError("certificates");
    const authData = field(object.authData, "auth_data");

    const leaf = parseCertificate(field(x5c[0], "certificate"));
    const intermediate = parseCertificate(field(x5c[1], "certificate"));
    const roots = (options.roots ?? [pemToDER(APPLE_APP_ATTESTATION_ROOT_PEM)]).map(parseCertificate);
    await verifyChain(leaf, intermediate, roots, options.now ?? new Date());

    // The app passes SHA-256 of the challenge as clientDataHash.
    const clientDataHash = await sha256(encoder.encode(input.challenge));
    const nonce = await sha256(concat(authData, clientDataHash));
    if (!equalBytes(certificateNonce(leaf), nonce)) throw new AttestError("nonce");

    const keyId = fromBase64(input.keyId);
    if (!equalBytes(await sha256(leaf.publicKey), keyId)) throw new AttestError("key_id");

    const data = parseAuthenticatorData(authData, true);
    if (!equalBytes(data.rpIdHash, await sha256(encoder.encode(options.appId)))) throw new AttestError("app_id");
    if (data.counter !== 0) throw new AttestError("counter");
    let environment: StoredKey["environment"];
    if (equalBytes(data.aaguid!, AAGUID_PRODUCTION)) environment = "production";
    else if (equalBytes(data.aaguid!, AAGUID_DEVELOPMENT)) environment = "development";
    else throw new AttestError("environment");
    if (!equalBytes(data.credentialId!, keyId)) throw new AttestError("credential");

    return { publicKey: toBase64(leaf.publicKey), counter: 0, environment };
  } catch (error) {
    if (error instanceof CBORError || error instanceof DERError) throw new AttestError("malformed");
    throw error;
  }
}

// MARK: - Assertion

/** Checks that `clientData` (the request body) was signed by the attested key; returns the new counter. */
export async function verifyAssertion(
  input: { assertion: string; clientData: Uint8Array },
  stored: StoredKey,
  appId: string,
): Promise<number> {
  try {
    const object = decodeCBOR(fromBase64(input.assertion));
    if (typeof object !== "object" || object === null || Array.isArray(object) || object instanceof Uint8Array) {
      throw new AttestError("format");
    }
    const signature = field(object.signature, "signature");
    const authenticatorData = field(object.authenticatorData, "auth_data");

    const clientDataHash = await sha256(input.clientData);
    const nonce = await sha256(concat(authenticatorData, clientDataHash));
    const key = await crypto.subtle.importKey("raw", fromBase64(stored.publicKey), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, ecdsaRaw(signature, 32), nonce);
    if (!valid) throw new AttestError("signature");

    const data = parseAuthenticatorData(authenticatorData, false);
    if (!equalBytes(data.rpIdHash, await sha256(encoder.encode(appId)))) throw new AttestError("app_id");
    if (data.counter <= stored.counter) throw new AttestError("replay");
    return data.counter;
  } catch (error) {
    if (error instanceof CBORError || error instanceof DERError) throw new AttestError("malformed");
    throw error;
  }
}

// MARK: - Storage

export const isValidKeyId = (value: string | null): value is string =>
  !!value && /^[A-Za-z0-9+/_=-]{40,64}$/.test(value);

export async function issueChallenge(kv: KVLike): Promise<string> {
  const challenge = toBase64(crypto.getRandomValues(new Uint8Array(32))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  await kv.put(`attest-challenge:${challenge}`, "1", { expirationTtl: CHALLENGE_TTL });
  return challenge;
}

/** Verifies an attestation against a challenge this server issued and stores the key. */
export async function registerKey(
  kv: KVLike,
  input: { keyId: string; attestation: string; challenge: string },
  options: AttestOptions,
): Promise<StoredKey> {
  const challengeKey = `attest-challenge:${input.challenge}`;
  if ((await kv.get(challengeKey)) !== "1") throw new AttestError("challenge");
  // One use: a stale marker that survives KV's eventual consistency only lives 60 s more.
  await kv.put(challengeKey, "used", { expirationTtl: 60 });
  const stored = await verifyAttestation(input, options);
  await kv.put(`attest-key:${input.keyId}`, JSON.stringify(stored), { expirationTtl: KEY_TTL });
  return stored;
}

/** Verifies an assertion over `body` from a registered key and records its counter. */
export async function checkAssertion(kv: KVLike, keyId: string, assertion: string, body: Uint8Array, appId: string): Promise<StoredKey> {
  const raw = await kv.get(`attest-key:${keyId}`);
  if (!raw) throw new AttestError("unknown_key");
  const stored = JSON.parse(raw) as StoredKey;
  const counter = await verifyAssertion({ assertion, clientData: body }, stored, appId);
  const updated = { ...stored, counter };
  await kv.put(`attest-key:${keyId}`, JSON.stringify(updated), { expirationTtl: KEY_TTL });
  return updated;
}
