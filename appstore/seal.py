#!/usr/bin/env python3
"""Seal a report in Actions so that only the Claude session that asked for it can read it.

Tenra's repository is public, and so are its Actions logs, so `ads.py` hides money and `asc.py`
refuses sales there. With a sealed run the keys stay in the repository secrets and the numbers
still reach the session: the session makes a key pair, passes the public key to the workflow
(`seal_to`), the workflow runs the script as it would run outside Actions with every line of its
output going to a file, and the log gets only that file sealed to the public key. The private key
never leaves the session's scratchpad.

    python3 appstore/seal.py keygen --out DIR        # DIR/seal-key.pem (private), prints the public key
    python3 appstore/seal.py seal --to PUBLIC < report.txt   # in Actions: SEALED lines for the log
    python3 appstore/seal.py open --key DIR/seal-key.pem < job.log   # in the session: the report

Sealing: a fresh AES-256-GCM key encrypts the text, RSA-OAEP (SHA-256) seals that key to the
public key (RSA, 3072 bits or more). The sealed text is base64 JSON, printed as `SEALED <n>/<total>
<chunk>` lines, so a log's timestamps and line breaks don't matter to `open`.
"""

import argparse
import base64
import json
import os
import re
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

CHUNK = 1000
MIN_BITS = 3072
OAEP = padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None)


def public_key(text: str) -> rsa.RSAPublicKey:
    """The public key as `keygen` prints it: base64 of the DER SubjectPublicKeyInfo (a PEM works too)."""
    text = text.strip()
    try:
        if text.startswith("-----BEGIN"):
            key = serialization.load_pem_public_key(text.encode())
        else:
            key = serialization.load_der_public_key(base64.b64decode("".join(text.split())))
    except ValueError as error:
        sys.exit(f"seal_to is not a public key from `seal.py keygen`: {error}")
    if not isinstance(key, rsa.RSAPublicKey) or key.key_size < MIN_BITS:
        sys.exit(f"seal_to must be an RSA public key of {MIN_BITS} bits or more")
    return key


def seal(text: bytes, key: rsa.RSAPublicKey) -> list[str]:
    aes = AESGCM.generate_key(bit_length=256)
    nonce = os.urandom(12)
    box = {
        "v": 1,
        "key": base64.b64encode(key.encrypt(aes, OAEP)).decode(),
        "nonce": base64.b64encode(nonce).decode(),
        "data": base64.b64encode(AESGCM(aes).encrypt(nonce, text, None)).decode(),
    }
    blob = base64.b64encode(json.dumps(box).encode()).decode()
    chunks = [blob[i:i + CHUNK] for i in range(0, len(blob), CHUNK)]
    return [f"SEALED {n}/{len(chunks)} {chunk}" for n, chunk in enumerate(chunks, 1)]


def unseal(log: str, key) -> list[str]:
    """Every sealed report in a log, in order. A log can hold several (one per step)."""
    reports, parts, total = [], {}, None
    for n, of, chunk in re.findall(r"SEALED (\d+)/(\d+) ([A-Za-z0-9+/=]+)", log):
        n, of = int(n), int(of)
        if n == 1:
            parts, total = {}, of
        parts[n] = chunk
        if total and len(parts) == total:
            box = json.loads(base64.b64decode("".join(parts[i] for i in range(1, total + 1))))
            aes = key.decrypt(base64.b64decode(box["key"]), OAEP)
            text = AESGCM(aes).decrypt(base64.b64decode(box["nonce"]), base64.b64decode(box["data"]), None)
            reports.append(text.decode("utf-8", errors="replace"))
            parts, total = {}, None
    return reports


def main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(prog="python3 appstore/seal.py", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    gen = sub.add_parser("keygen", help="make a key pair: the private key to a file, the public key printed")
    gen.add_argument("--out", required=True, help="directory for seal-key.pem (the session's scratchpad)")
    put = sub.add_parser("seal", help="seal standard input to a public key")
    put.add_argument("--to", required=True, help="the public key `keygen` printed")
    get = sub.add_parser("open", help="read the sealed reports in a log from standard input")
    get.add_argument("--key", required=True, help="the private key file from `keygen`")
    args = parser.parse_args(argv)

    if args.command == "keygen":
        os.makedirs(args.out, exist_ok=True)
        key = rsa.generate_private_key(public_exponent=65537, key_size=MIN_BITS)
        path = os.path.join(args.out, "seal-key.pem")
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption()))
        der = key.public_key().public_bytes(serialization.Encoding.DER,
                                            serialization.PublicFormat.SubjectPublicKeyInfo)
        print(base64.b64encode(der).decode())
    elif args.command == "seal":
        for line in seal(sys.stdin.buffer.read(), public_key(args.to)):
            print(line)
    else:
        with open(args.key, "rb") as f:
            key = serialization.load_pem_private_key(f.read(), password=None)
        reports = unseal(sys.stdin.read(), key)
        if not reports:
            sys.exit("No sealed report in the input")
        print("\n\n".join(reports))


if __name__ == "__main__":
    main(sys.argv[1:])
