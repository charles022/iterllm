For *“a systemd service that runs at startup, connects to the network, and needs an API key; we don’t want plaintext at rest; we may rotate/update the key”*, the best fit is:

## Use the **system (root-targeted) encrypted credential** + `LoadCredentialEncrypted=`

That means:

* encrypt the secret **for the system manager** (PID 1) using `systemd-creds encrypt` (no `--user`)
* store the encrypted blob in `/etc/credstore.encrypted/…`
* have the **system service unit** load it with `LoadCredentialEncrypted=`
* your service reads the plaintext from `$CREDENTIALS_DIRECTORY/<name>` (systemd mounts it only for that service at runtime) ([Systemd][1])

This is the “intended” pattern for boot-time services: the service starts reliably at boot without requiring your user session to be logged in, and the key is not stored unencrypted on disk. ([Systemd][1])

---

# Why this is best for that scenario

## 1) Boot-time reliability (no user login required)

A startup service typically runs under the **system manager**, not your user session. If you used a user-targeted credential, the service wouldn’t be able to start at boot unless you also rely on lingering + the user manager being active in a particular way (and even then, it’s not the normal pattern). System credentials avoid that.

## 2) “Not plaintext at rest”

Encrypted credentials are explicitly designed for “storage of the data at rest” and use authenticated encryption (AES-GCM) with keys derived from TPM2 and/or `/var/lib/systemd/credential.secret`. ([Systemd][1])

## 3) Clean key rotation

Updating the key is just:

* replace the encrypted `.cred` file
* restart the service

You don’t have to edit the unit file or touch environment files.

---

# Concrete recommended implementation

## A) Create/replace the encrypted credential

```bash
sudo mkdir -p /etc/credstore.encrypted
sudo chmod 0700 /etc/credstore.encrypted

sudo systemd-ask-password "Enter API key for myservice:" \
  | sudo systemd-creds encrypt --name=MY_API_KEY - \
    /etc/credstore.encrypted/myservice.my_api_key.cred

sudo chmod 0600 /etc/credstore.encrypted/myservice.my_api_key.cred
sudo chown root:root /etc/credstore.encrypted/myservice.my_api_key.cred
```

## B) Load it in your system unit

In `myservice.service`:

```ini
[Service]
LoadCredentialEncrypted=MY_API_KEY:/etc/credstore.encrypted/myservice.my_api_key.cred
PrivateMounts=yes
ExecStart=/usr/local/bin/myservice
```

`LoadCredentialEncrypted=` is documented in `systemd.exec(5)` and is the systemd directive that decrypts and passes the credential to the service. ([Freedesktop][2])

## C) Read it in the service

systemd makes it available as a file under `$CREDENTIALS_DIRECTORY` for the running process context. ([man7.org][3])

So your program reads:

* `$CREDENTIALS_DIRECTORY/MY_API_KEY`

If you’re writing the service in a language where you want a stable path, you can also pass `%d/MY_API_KEY` as an argument (where `%d` expands to the credential dir), but the environment variable approach is canonical.

---

# How to rotate/update the key (safely)

1. Re-encrypt (overwrite the cred file):

```bash
sudo systemd-ask-password "Enter NEW API key for myservice:" \
  | sudo systemd-creds encrypt --name=MY_API_KEY - \
    /etc/credstore.encrypted/myservice.my_api_key.cred
```

2. Restart:

```bash
sudo systemctl restart myservice.service
```

That’s it. No plaintext file, no unit changes.

---

# Two important operational notes

## 1) Backups and portability

The encrypted credential is typically decryptable only on the machine that has the matching decryption material (TPM and/or `/var/lib/systemd/credential.secret`). That’s usually what you want, but it affects “copy to another box and it works.”

The credentials design explicitly mentions encryption keys derived from TPM2 and/or `/var/lib/systemd/credential.secret`. ([Systemd][1])

## 2) Interactive access without `sudo`

For *this specific scenario*, interactive access without `sudo` is **not the goal** and is generally not desirable: it would mean any user could read a system service’s key. If you also need interactive access for a dev tool, that’s where you keep a **separate user-targeted credential**.

(So: system service uses system credential; dev tooling uses user credential.)

---

If you tell me what kind of service it is (your own binary vs nginx vs some wrapper script), I’ll show the cleanest pattern to read `$CREDENTIALS_DIRECTORY/MY_API_KEY` and inject it into the app *without* ever exporting it globally.

[1]: https://systemd.io/CREDENTIALS/?utm_source=chatgpt.com "System and Service Credentials"
[2]: https://www.freedesktop.org/software/systemd/man/systemd.exec.html?utm_source=chatgpt.com "systemd.exec"
[3]: https://man7.org/linux/man-pages/man1/systemd-creds.1.html?utm_source=chatgpt.com "systemd-creds(1) - Linux manual page"

