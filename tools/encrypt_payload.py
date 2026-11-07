#!/usr/bin/env python3
"""Encrypt/decrypt Valhalla framework payload files (VALENC1 format).

Format (all integers little-endian):
  header: 8-byte magic b"VALENC1\\x00", uint32 chunk_size (plaintext bytes per chunk)
  per chunk: uint32 cipher_len (ciphertext + 16-byte GCM tag), 12-byte nonce, cipher bytes

Key: 32-byte AES-256 key read from a key file (default C:\\Ai\\valhalla-key.bin).
The key file itself must NEVER be committed; runtime code embeds it obfuscated.

Usage:
  python encrypt_payload.py enc <in> <out.enc> [--key KEYFILE]
  python encrypt_payload.py dec <in.enc> <out> [--key KEYFILE]
  python encrypt_payload.py verify <in.enc> [--key KEYFILE]
"""
import hashlib
import os
import struct
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAGIC = b"VALENC1\x00"
CHUNK = 1 << 20
DEFAULT_KEY = r"C:\Ai\valhalla-key.bin"


def load_key(path):
    data = open(path, "rb").read()
    if len(data) != 32:
        raise SystemExit(f"key must be 32 bytes, got {len(data)}")
    return data


def encrypt(src, dst, key):
    aes = AESGCM(key)
    total = os.path.getsize(src)
    done = 0
    with open(src, "rb") as fin, open(dst, "wb") as fout:
        fout.write(MAGIC)
        fout.write(struct.pack("<I", CHUNK))
        while True:
            plain = fin.read(CHUNK)
            if not plain:
                break
            nonce = os.urandom(12)
            cipher = aes.encrypt(nonce, plain, MAGIC)
            fout.write(struct.pack("<I", len(cipher)))
            fout.write(nonce)
            fout.write(cipher)
            done += len(plain)
    return total, os.path.getsize(dst)


def decrypt_stream(fin, key, out_write):
    aes = AESGCM(key)
    magic = fin.read(8)
    if magic != MAGIC:
        raise SystemExit("not a VALENC1 file")
    (chunk_size,) = struct.unpack("<I", fin.read(4))
    plain_total = 0
    while True:
        head = fin.read(4)
        if not head:
            break
        (clen,) = struct.unpack("<I", head)
        nonce = fin.read(12)
        cipher = fin.read(clen)
        plain = aes.decrypt(nonce, cipher, MAGIC)
        if len(plain) > chunk_size:
            raise SystemExit("chunk larger than declared size")
        out_write(plain)
        plain_total += len(plain)
    return plain_total


def decrypt(src, dst, key):
    h = hashlib.sha256()
    with open(src, "rb") as fin, open(dst, "wb") as fout:
        return decrypt_stream(fin, key, lambda b: (fout.write(b), h.update(b))[1])


def verify(src, key):
    h = hashlib.sha256()
    with open(src, "rb") as fin:
        n = decrypt_stream(fin, key, h.update)
    return n, h.hexdigest()


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    cmd = argv[1]
    key_path = DEFAULT_KEY
    if "--key" in argv:
        i = argv.index("--key")
        key_path = argv[i + 1]
    key = load_key(key_path)
    if cmd == "enc":
        total, out = encrypt(argv[2], argv[3], key)
        print(f"enc {argv[2]} {total} -> {argv[3]} {out}")
    elif cmd == "dec":
        n = decrypt(argv[2], argv[3], key)
        print(f"dec {argv[2]} -> {argv[3]} plain={n}")
    elif cmd == "verify":
        n, digest = verify(argv[2], key)
        print(f"verify ok plain={n} sha256={digest}")
    else:
        raise SystemExit(f"unknown command {cmd}")


if __name__ == "__main__":
    main(sys.argv)
