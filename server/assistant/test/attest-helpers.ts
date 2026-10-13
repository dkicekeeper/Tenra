import { fromBase64, toBase64 } from "../src/appattest";
import fixture from "./fixtures/appattest.json";

// Shared by the App Attest tests: a CBOR encoder and assertions signed with the fixture's leaf
// key (test/fixtures/make-appattest.mjs), the way the app's DCAppAttestService signs a body.

export type Encodable = number | string | Uint8Array | Encodable[] | { [key: string]: Encodable };

function head(major: number, length: number): number[] {
  if (length < 24) return [(major << 5) | length];
  if (length < 256) return [(major << 5) | 24, length];
  if (length < 65536) return [(major << 5) | 25, length >> 8, length & 0xff];
  return [(major << 5) | 26, (length >>> 24) & 0xff, (length >> 16) & 0xff, (length >> 8) & 0xff, length & 0xff];
}

export function cbor(value: Encodable): Uint8Array {
  if (typeof value === "number") return Uint8Array.from(head(0, value));
  if (typeof value === "string") {
    const bytes = new TextEncoder().encode(value);
    return Uint8Array.from([...head(3, bytes.length), ...bytes]);
  }
  if (value instanceof Uint8Array) return Uint8Array.from([...head(2, value.length), ...value]);
  if (Array.isArray(value)) return Uint8Array.from([...head(4, value.length), ...value.flatMap((v) => [...cbor(v)])]);
  const entries = Object.entries(value);
  return Uint8Array.from([...head(5, entries.length), ...entries.flatMap(([k, v]) => [...cbor(k), ...cbor(v)])]);
}


const sha256 = async (bytes: Uint8Array) => new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));

function derSignature(raw: Uint8Array): Uint8Array {
  const integer = (bytes: Uint8Array) => {
    let start = 0;
    while (start < bytes.length - 1 && bytes[start] === 0) start++;
    let trimmed = bytes.subarray(start);
    if (trimmed[0]! & 0x80) trimmed = Uint8Array.from([0, ...trimmed]);
    return [0x02, trimmed.length, ...trimmed];
  };
  const body = [...integer(raw.subarray(0, 32)), ...integer(raw.subarray(32))];
  return Uint8Array.from([0x30, body.length, ...body]);
}

export async function assertion(body: Uint8Array, counter: number, appId = fixture.appId): Promise<string> {
  const authenticatorData = new Uint8Array(37);
  authenticatorData.set(await sha256(new TextEncoder().encode(appId)));
  new DataView(authenticatorData.buffer).setUint32(33, counter);
  const nonce = await sha256(Uint8Array.from([...authenticatorData, ...(await sha256(body))]));
  const key = await crypto.subtle.importKey("pkcs8", fromBase64(fixture.leafPrivateKey), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, nonce));
  return toBase64(cbor({ signature: derSignature(raw), authenticatorData }));
}

/** The fixture's key as the server stores it once registered. */
export async function storedKey(): Promise<string> {
  const leaf = fromBase64(fixture.leaf);
  // The raw point is the last 65 bytes of the leaf's SubjectPublicKeyInfo; read it from the
  // certificate through the server's own parser.
  const { parseCertificate } = await import("../src/der");
  return JSON.stringify({ publicKey: toBase64(parseCertificate(leaf).publicKey), counter: 0, environment: "development" });
}
