// Just enough DER and X.509 to check an App Attest certificate chain with WebCrypto: the
// to-be-signed bytes, the signature and its algorithm, the subject public key, validity,
// names and extensions. Only the low tag numbers and definite lengths DER allows.

export class DERError extends Error {}

export interface TLV {
  tag: number;
  /** The whole element, header included. */
  raw: Uint8Array;
  /** The contents only. */
  value: Uint8Array;
}

export function readTLV(bytes: Uint8Array, offset = 0): { tlv: TLV; next: number } {
  if (offset + 2 > bytes.length) throw new DERError("truncated");
  const tag = bytes[offset]!;
  if ((tag & 0x1f) === 0x1f) throw new DERError("high tag number");
  let length = bytes[offset + 1]!;
  let header = 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new DERError("bad length");
    if (offset + 2 + count > bytes.length) throw new DERError("truncated");
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + bytes[offset + 2 + i]!;
    header += count;
  }
  const end = offset + header + length;
  if (end > bytes.length) throw new DERError("truncated");
  return {
    tlv: { tag, raw: bytes.subarray(offset, end), value: bytes.subarray(offset + header, end) },
    next: end,
  };
}

export function children(tlv: TLV): TLV[] {
  const items: TLV[] = [];
  let offset = 0;
  while (offset < tlv.value.length) {
    const { tlv: child, next } = readTLV(tlv.value, offset);
    items.push(child);
    offset = next;
  }
  return items;
}

function firstChild(tlv: TLV): TLV {
  const [first] = children(tlv);
  if (!first) throw new DERError("empty");
  return first;
}

export function decodeOID(value: Uint8Array): string {
  if (value.length === 0) throw new DERError("empty oid");
  const first = value[0]!;
  const parts = [Math.floor(first / 40), first % 40];
  let current = 0;
  for (let i = 1; i < value.length; i++) {
    const byte = value[i]!;
    current = current * 128 + (byte & 0x7f);
    if (!(byte & 0x80)) {
      parts.push(current);
      current = 0;
    }
  }
  return parts.join(".");
}

function decodeTime(tlv: TLV): Date {
  const text = new TextDecoder().decode(tlv.value);
  let iso: string;
  if (tlv.tag === 0x17) {
    // UTCTime YYMMDDHHMMSSZ: years 50-99 are 19xx.
    const year = Number(text.slice(0, 2));
    iso = `${year >= 50 ? 1900 + year : 2000 + year}-${text.slice(2, 4)}-${text.slice(4, 6)}T${text.slice(6, 8)}:${text.slice(8, 10)}:${text.slice(10, 12)}Z`;
  } else if (tlv.tag === 0x18) {
    iso = `${text.slice(0, 4)}-${text.slice(4, 6)}-${text.slice(6, 8)}T${text.slice(8, 10)}:${text.slice(10, 12)}:${text.slice(12, 14)}Z`;
  } else {
    throw new DERError("bad time");
  }
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) throw new DERError("bad time");
  return date;
}

export interface Certificate {
  tbs: Uint8Array;
  signatureAlgorithm: string;
  /** The DER ECDSA-Sig-Value. */
  signature: Uint8Array;
  issuer: Uint8Array;
  subject: Uint8Array;
  notBefore: Date;
  notAfter: Date;
  /** The whole SubjectPublicKeyInfo, for WebCrypto's "spki" import. */
  spki: Uint8Array;
  curve: string;
  /** The raw public key (an uncompressed EC point). */
  publicKey: Uint8Array;
  /** Extension values by OID (the contents of extnValue). */
  extensions: Map<string, Uint8Array>;
}

export const OID = {
  ecdsaSHA256: "1.2.840.10045.4.3.2",
  ecdsaSHA384: "1.2.840.10045.4.3.3",
  p256: "1.2.840.10045.3.1.7",
  p384: "1.3.132.0.34",
  appAttestNonce: "1.2.840.113635.100.8.2",
} as const;

export function parseCertificate(der: Uint8Array): Certificate {
  const { tlv: certificate, next } = readTLV(der);
  if (next !== der.length || certificate.tag !== 0x30) throw new DERError("not a certificate");
  const [tbs, algorithm, signature] = children(certificate);
  if (!tbs || !algorithm || !signature || signature.tag !== 0x03) throw new DERError("not a certificate");

  const fields = children(tbs);
  let index = fields[0]?.tag === 0xa0 ? 1 : 0; // [0] version
  index += 1; // serialNumber
  index += 1; // signature algorithm (repeated)
  const issuer = fields[index++];
  const validity = fields[index++];
  const subject = fields[index++];
  const spki = fields[index++];
  if (!issuer || !validity || !subject || !spki) throw new DERError("short tbs");

  const [notBefore, notAfter] = children(validity);
  const [spkiAlgorithm, spkiKey] = children(spki);
  if (!spkiAlgorithm) throw new DERError("bad tbs");
  const [, curveOID] = children(spkiAlgorithm);
  if (!notBefore || !notAfter || !spkiKey || !curveOID) throw new DERError("bad tbs");

  const extensions = new Map<string, Uint8Array>();
  for (const field of fields.slice(index)) {
    if (field.tag !== 0xa3) continue;
    const [list] = children(field);
    if (!list) continue;
    for (const extension of children(list)) {
      const parts = children(extension);
      const id = parts[0];
      const value = parts[parts.length - 1];
      if (id && value) extensions.set(decodeOID(id.value), value.value);
    }
  }

  return {
    tbs: tbs.raw,
    signatureAlgorithm: decodeOID(firstChild(algorithm).value),
    signature: signature.value.subarray(1), // skip the unused-bits byte
    issuer: issuer.raw,
    subject: subject.raw,
    notBefore: decodeTime(notBefore),
    notAfter: decodeTime(notAfter),
    spki: spki.raw,
    curve: decodeOID(curveOID.value),
    publicKey: spkiKey.value.subarray(1),
    extensions,
  };
}

/** DER ECDSA-Sig-Value → the r‖s form WebCrypto verifies. */
export function ecdsaRaw(der: Uint8Array, size: number): Uint8Array {
  const { tlv } = readTLV(der);
  const [r, s] = children(tlv);
  if (tlv.tag !== 0x30 || r?.tag !== 0x02 || s?.tag !== 0x02) throw new DERError("bad signature");
  const out = new Uint8Array(size * 2);
  const place = (integer: Uint8Array, at: number) => {
    let start = 0;
    while (start < integer.length - 1 && integer[start] === 0) start++;
    const bytes = integer.subarray(start);
    if (bytes.length > size) throw new DERError("bad signature");
    out.set(bytes, at + size - bytes.length);
  };
  place(r.value, 0);
  place(s.value, size);
  return out;
}

export function pemToDER(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) CERTIFICATE-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

export function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}
