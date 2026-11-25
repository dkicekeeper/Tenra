#!/usr/bin/env python3
"""Offline tests of appstore/seal.py: python3 -I appstore/test_seal.py"""

import base64
import contextlib
import importlib.util
import io
import os
import tempfile
import unittest
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

spec = importlib.util.spec_from_file_location("seal", Path(__file__).resolve().with_name("seal.py"))
seal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(seal)


def keygen(directory: str) -> str:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        seal.main(["keygen", "--out", directory])
    return out.getvalue().strip()


class SealTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.public = keygen(self.dir.name)
        with open(os.path.join(self.dir.name, "seal-key.pem"), "rb") as f:
            self.private = serialization.load_pem_private_key(f.read(), password=None)

    def tearDown(self):
        self.dir.cleanup()

    def test_private_key_is_owner_only(self):
        mode = os.stat(os.path.join(self.dir.name, "seal-key.pem")).st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def test_round_trip_through_a_log_with_timestamps(self):
        report = ("| Campaign | Spend |\n| KZ-Category | 41.20 USD |\nстрока " + os.urandom(3000).hex()).encode()
        lines = seal.seal(report, seal.public_key(self.public))
        self.assertGreater(len(lines), 1)
        log = "\n".join(f"2026-11-25T18:00:0{i % 10}.1234567Z {line}" for i, line in enumerate(lines))
        self.assertEqual(seal.unseal("noise\n" + log + "\nmore noise", self.private), [report.decode()])

    def test_the_log_holds_no_plain_text(self):
        lines = seal.seal(b"KZ-Category 41.20 USD", seal.public_key(self.public))
        self.assertNotIn("41.20", "\n".join(lines))
        self.assertNotIn(b"41.20", base64.b64decode("".join(l.split()[2] for l in lines)))

    def test_a_long_table_takes_few_lines(self):
        table = "".join(f"| 2026-11-{d:02d} | download | Tenra | KZ | {d} |  |\n" for d in range(1, 31)) * 8
        self.assertLessEqual(len(seal.seal(table.encode(), seal.public_key(self.public))), 3)

    def test_the_first_form_still_opens(self):
        aes = seal.AESGCM.generate_key(bit_length=256)
        nonce = os.urandom(12)
        box = {"v": 1, "key": base64.b64encode(self.private.public_key().encrypt(aes, seal.OAEP)).decode(),
               "nonce": base64.b64encode(nonce).decode(),
               "data": base64.b64encode(seal.AESGCM(aes).encrypt(nonce, b"old", None)).decode()}
        blob = base64.b64encode(seal.json.dumps(box).encode()).decode()
        self.assertEqual(seal.unseal(f"SEALED 1/1 {blob}", self.private), ["old"])

    def test_two_reports_in_one_log(self):
        key = seal.public_key(self.public)
        log = "\n".join(seal.seal(b"first", key) + ["step two"] + seal.seal(b"second", key))
        self.assertEqual(seal.unseal(log, self.private), ["first", "second"])

    def test_pem_public_key_is_accepted(self):
        pem = self.private.public_key().public_bytes(serialization.Encoding.PEM,
                                                     serialization.PublicFormat.SubjectPublicKeyInfo).decode()
        self.assertEqual(seal.unseal("\n".join(seal.seal(b"ok", seal.public_key(pem))), self.private), ["ok"])

    def test_short_key_is_refused(self):
        small = rsa.generate_private_key(public_exponent=65537, key_size=2048).public_key()
        der = small.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
        with self.assertRaises(SystemExit):
            seal.public_key(base64.b64encode(der).decode())

    def test_garbage_is_refused(self):
        with self.assertRaises(SystemExit):
            seal.public_key("not a key")

    def test_another_key_cannot_open(self):
        other = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        lines = seal.seal(b"secret", seal.public_key(self.public))
        with self.assertRaises(ValueError):
            seal.unseal("\n".join(lines), other)


if __name__ == "__main__":
    unittest.main()
