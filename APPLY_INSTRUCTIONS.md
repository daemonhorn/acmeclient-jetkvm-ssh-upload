# How to apply this and open the PR

**Use Option A.** It has been verified (2026-08-10) to `git am` cleanly
against the current `opnsense/plugins` `master`.

## Option A: apply the patch file (recommended, verified working)

```sh
git clone https://github.com/<your-fork>/plugins.git
cd plugins
git checkout -b feature/acmeclient-jetkvm-ssh-upload master
git am 0001-security-acme-client-add-automation-to-upload-certif.patch
git push origin feature/acmeclient-jetkvm-ssh-upload
```

## Option B: fetch from the bundle (best-effort, currently broken)

```sh
git clone https://github.com/<your-fork>/plugins.git
cd plugins
git fetch acmeclient-jetkvm-ssh-upload.bundle \
  feature/acmeclient-jetkvm-ssh-upload:feature/acmeclient-jetkvm-ssh-upload
git checkout feature/acmeclient-jetkvm-ssh-upload
git push origin feature/acmeclient-jetkvm-ssh-upload
```

The bundle was made from a shallow clone and does **not** carry a
complete, fetchable history: `git bundle verify` reports it as OK, but
actually cloning from it fails —

```
error: Could not read 8254e5685b5c12b269c1f413f512da4d111bfa1c
fatal: Failed to traverse parents of commit 6ba7d56ff776a9425adf2b0539a37ae9a0df7a76
fatal: remote did not send all necessary objects
```

— because it references `opnsense/plugins` history objects it never
packed. Don't rely on it; use Option A. The bundle is kept here only as
a secondary artifact in case a full-history clone happens to already
have those objects.

## Before opening the PR

1. **Test on real JetKVM hardware if at all possible.** The PR
   description flags the biggest open question: whether
   `/userdata/jetkvm/tls` really is where a dropped `fullchain.pem` /
   `privkey.pem` gets picked up by JetKVM's "Custom" TLS mode on your
   firmware version, and whether any restart command is actually needed
   or possible. I could not verify this against a physical device.
2. Replace the changelog placeholder in `security/acme-client/pkg-descr`
   (`(#XXXX)`) with the real PR number once GitHub assigns one — this is
   the convention used throughout that file's changelog.
3. Open the PR against `opnsense/plugins` (base: `master`) using the
   title and body in `PR_DESCRIPTION.md`.

## Files in this delivery

- `0001-security-acme-client-add-automation-to-upload-certif.patch` —
  the change as a single `git am`-able patch.
- `acmeclient-jetkvm-ssh-upload.bundle` — the same commit as a git
  bundle (alternate way to pull it in).
- `PR_DESCRIPTION.md` — suggested PR title/body.
- `APPLY_INSTRUCTIONS.md` — this file.
