# How to apply this and open the PR

Both options below are verified working (2026-08-11), against the
current `opnsense/plugins` `master`, with one caveat on Option B.

## Option A: apply the patch file (recommended)

```sh
git clone https://github.com/<your-fork>/plugins.git
cd plugins
git checkout -b feature/acmeclient-jetkvm-ssh-upload master
git am 0001-security-acme-client-add-automation-to-upload-certif.patch
git push origin feature/acmeclient-jetkvm-ssh-upload
```

## Option B: fetch from the bundle

```sh
git clone https://github.com/<your-fork>/plugins.git
cd plugins
git fetch acmeclient-jetkvm-ssh-upload.bundle \
  feature/acmeclient-jetkvm-ssh-upload:feature/acmeclient-jetkvm-ssh-upload
git checkout feature/acmeclient-jetkvm-ssh-upload
git push origin feature/acmeclient-jetkvm-ssh-upload
```

This works — confirmed by fetching it into a real clone of
`opnsense/plugins` — **as long as step 1 is a real `git clone` of the
actual repo** (not the bundle itself). The bundle was built from a
shallow clone, so it doesn't carry a complete standalone history:
running `git clone acmeclient-jetkvm-ssh-upload.bundle` directly (skip
step 1, clone the bundle on its own) fails with `remote did not send
all necessary objects`, because it references upstream objects it never
packed. `git fetch <bundle> ...` into an existing full clone works
because those objects are already present there. Use Option A if in
doubt.

## Before opening the PR

1. **Hardware validation done (2026-08-11).** Tested directly against a
   real JetKVM device over SSH:
   - `/userdata/jetkvm/tls` is confirmed correct as the storage
     directory for "Custom" TLS mode.
   - The filenames were **wrong** in the first draft and have been
     corrected: JetKVM's "Custom" TLS mode reads `user-defined.crt` /
     `user-defined.key`, not `fullchain.pem` / `privkey.pem`. The
     script defaults and model/dialog help text now reflect this.
   - JetKVM does not hot-reload a "Custom" certificate; its own
     apply script does a full device `reboot`. The post-upload command
     field's help text says this explicitly; the field is still blank
     by default since a reboot briefly drops any active KVM-over-IP
     session — set it to `reboot` yourself if you want it applied
     automatically.
   - The remote write was changed from truncating the live cert/key
     files in place to staging them under temporary names and
     atomically `mv`-ing them into place, validated end-to-end against
     the device (including cleanup) using throwaway filenames, so the
     real device certificates were never touched by this testing.
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
