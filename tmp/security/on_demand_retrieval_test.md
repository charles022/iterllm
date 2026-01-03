
---

# Test 0 — File exists + permissions are correct (no secret exposure)

```bash
sudo stat -c 'mode=%a owner=%U group=%G path=%n' /etc/credstore.encrypted
sudo stat -c 'mode=%a owner=%U group=%G path=%n' /etc/credstore.encrypted/codexkey
sudo ls -l /etc/credstore.encrypted/codexkey
```

**Expected**

* `/etc/credstore.encrypted` → `700 root root`
* `/etc/credstore.encrypted/codexkey` → `600 root root`

---

# Test 1 — Prove it’s not plaintext at rest (no decrypt)

Hex view (first 128 bytes):

```bash
sudo head -c 128 /etc/credstore.encrypted/codexkey | hexdump -C
```

Strings scan (shouldn’t show your real API key):

```bash
sudo strings -n 12 /etc/credstore.encrypted/codexkey | head
```

**Expected**

* looks like random-ish data / base64-ish chunks
* not an obvious API key

---

# Test 2 — Decrypt once and print only a safe proof (len + prefix/suffix)

This decrypts to stdout but prints only:

* length
* first 4 chars
* last 4 chars

```bash
sudo systemd-creds decrypt /etc/credstore.encrypted/codexkey - \
  | python3 - <<'PY'
import sys

s = sys.stdin.read().strip("\n")
n = len(s)

prefix = s[:4]
suffix = s[-4:] if n >= 4 else s

print(f"len={n} prefix={prefix!r} suffix={suffix!r}")
PY
```

**Expected**

* `len` is non-zero
* prefix/suffix match what you expect (keep this output private)

---

# Test 3 — Safer alternative: length + short hash fingerprint

If you want to avoid revealing even prefix/suffix, use a short SHA-256 fingerprint:

```bash
sudo systemd-creds decrypt /etc/credstore.encrypted/codexkey - \
  | python3 - <<'PY'
import sys, hashlib

s = sys.stdin.read().strip("\n")
h = hashlib.sha256(s.encode("utf-8")).hexdigest()[:16]

print(f"len={len(s)} sha256_16={h}")
PY
```

---

# Test 4 — Confirm “many uses during execution” (decrypt once, reuse in-memory)

This demonstrates your Python caching behavior (only one decrypt call per run).

```bash
sudo python3 - <<'PY'
import time
import subprocess
from pathlib import Path
from functools import lru_cache

CRED_FILE = Path("/etc/credstore.encrypted/codexkey")

def _decrypt(path: Path) -> str:
    p = subprocess.Popen(
        ["systemd-creds", "decrypt", str(path), "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    out, err = p.communicate()
    if p.returncode != 0:
        raise RuntimeError(err.strip())
    return out.strip()

@lru_cache(maxsize=1)
def load_api_key() -> str:
    return _decrypt(CRED_FILE)

t0 = time.time()
k1 = load_api_key()
t1 = time.time()

for _ in range(1000):
    k2 = load_api_key()

assert k1 == k2

t2 = time.time()

print("first_call_ms=", int((t1 - t0) * 1000))
print("cached_1000_calls_ms=", int((t2 - t1) * 1000))
print("len=", len(k1), "prefix=", repr(k1[:4]), "suffix=", repr(k1[-4:]))
PY
```

**Expected**

* `cached_1000_calls_ms` is tiny compared to the first call
* length/prefix/suffix stable

---

# Test 5 — Confirm sudo caching (no repeated password prompts)

This checks that once you’ve authenticated to sudo, subsequent decrypts don’t prompt again during the sudo timeout window.

```bash
sudo -v
for i in 1 2 3; do
  sudo systemd-creds decrypt /etc/credstore.encrypted/codexkey - >/dev/null
  echo "ok $i"
done
```

---

