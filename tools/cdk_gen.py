# -*- coding: utf-8 -*-
"""Generate VAL-DAL online-edition CDK codes (matches the client-side check).

Usage: python tools/cdk_gen.py [PRO|MAX|ENT] [count]
Code: VALDAL-<PLAN>-<6>-<6>-<check>
check = CHARSET[(sum(char codes of everything before it, dashes removed) * 31 + 17) % 36]
Redemption in the desktop clients is local/offline for the alpha; move the
same check server-side before public sale.
"""
import random
import string
import sys

CS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def make(plan: str) -> str:
    pool = string.ascii_uppercase + string.digits
    seg = lambda: "".join(random.choice(pool) for _ in range(6))
    flat_body = f"VALDAL{plan}{seg()}{seg()}"
    check = CS[(sum(ord(c) for c in flat_body) * 31 + 17) % 36]
    flat = flat_body + check
    return f"VALDAL-{plan}-{flat[9:15]}-{flat[15:21]}-{check}"


def valid(code: str) -> bool:
    parts = code.upper().replace(" ", "").split("-")
    if len(parts) != 5 or parts[0] != "VALDAL" or parts[1] not in ("PRO", "MAX", "ENT"):
        return False
    flat = "".join(parts)
    return CS[(sum(ord(c) for c in flat[:-1]) * 31 + 17) % 36] == flat[-1]


if __name__ == "__main__":
    plan = (sys.argv[1] if len(sys.argv) > 1 else "PRO").upper()
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    for _ in range(n):
        code = make(plan)
        assert valid(code)
        print(code)
