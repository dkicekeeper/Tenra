// A minimal CBOR decoder (RFC 8949) for App Attest objects: unsigned and negative integers,
// byte and text strings, arrays and maps, true/false/null. Definite lengths only, which is all
// Apple produces. Maps with text keys become plain objects; byte strings stay Uint8Array.

export class CBORError extends Error {}

export type CBORValue = number | string | boolean | null | Uint8Array | CBORValue[] | { [key: string]: CBORValue };

export function decodeCBOR(bytes: Uint8Array): CBORValue {
  const reader = new Reader(bytes);
  const value = reader.value();
  if (reader.offset !== bytes.length) throw new CBORError("trailing bytes");
  return value;
}

class Reader {
  offset = 0;
  private depth = 0;

  constructor(private readonly bytes: Uint8Array) {}

  private byte(): number {
    if (this.offset >= this.bytes.length) throw new CBORError("truncated");
    return this.bytes[this.offset++]!;
  }

  private take(length: number): Uint8Array {
    if (length > this.bytes.length - this.offset) throw new CBORError("truncated");
    const slice = this.bytes.subarray(this.offset, this.offset + length);
    this.offset += length;
    return slice;
  }

  private argument(info: number): number {
    if (info < 24) return info;
    let size: number;
    if (info === 24) size = 1;
    else if (info === 25) size = 2;
    else if (info === 26) size = 4;
    else if (info === 27) size = 8;
    else throw new CBORError("indefinite length");
    let value = 0;
    for (let i = 0; i < size; i++) value = value * 256 + this.byte();
    if (!Number.isSafeInteger(value)) throw new CBORError("integer too large");
    return value;
  }

  value(): CBORValue {
    if (++this.depth > 16) throw new CBORError("too deep");
    try {
      const initial = this.byte();
      const major = initial >> 5;
      const info = initial & 0x1f;
      switch (major) {
        case 0:
          return this.argument(info);
        case 1:
          return -1 - this.argument(info);
        case 2:
          return this.take(this.argument(info)).slice();
        case 3:
          return new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(this.take(this.argument(info)));
        case 4: {
          const count = this.argument(info);
          const items: CBORValue[] = [];
          for (let i = 0; i < count; i++) items.push(this.value());
          return items;
        }
        case 5: {
          const count = this.argument(info);
          const map: { [key: string]: CBORValue } = {};
          for (let i = 0; i < count; i++) {
            const key = this.value();
            if (typeof key !== "string") throw new CBORError("non-text map key");
            map[key] = this.value();
          }
          return map;
        }
        case 7:
          if (info === 20) return false;
          if (info === 21) return true;
          if (info === 22) return null;
          throw new CBORError("unsupported simple value");
        default:
          throw new CBORError("unsupported major type");
      }
    } finally {
      this.depth--;
    }
  }
}
