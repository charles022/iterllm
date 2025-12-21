import subprocess
from pathlib import Path
from functools import lru_cache

# usage:
# API_KEY = load_api_key()
# Safe to reuse API_KEY many times during execution

CRED_FILE = Path("/etc/credstore.encrypted/codexkey.cred")

def _decrypt_credential(path: Path) -> str:
    p = subprocess.Popen(
        ["systemd-creds", "decrypt", str(path), "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    out, err = p.communicate()
    if p.returncode != 0:
        raise RuntimeError(f"Credential decryption failed: {err.strip()}")
    return out.strip()

@lru_cache(maxsize=1)
def load_api_key() -> str:
    if not CRED_FILE.exists():
        raise FileNotFoundError(f"Encrypted credential not found: {CRED_FILE}")
    return _decrypt_credential(CRED_FILE)

