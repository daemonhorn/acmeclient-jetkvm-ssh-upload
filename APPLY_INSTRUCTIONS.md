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
`opnsense/plugins` and then checking for missing objects with
`git rev-list --objects --missing=print <ref>` (0 of ~9,800 objects
missing) — **as long as step 1 is a real `git clone` of the actual
repo** (not the bundle itself, and not a partial/blob-filtered clone,
which can silently backfill missing blobs from GitHub and mask a
genuinely incomplete bundle). An earlier version of this bundle was
built from a shallow, blob-filtered clone and was **not** actually
self-contained; it has since been rebuilt from a full, unfiltered clone
and re-verified with the missing-objects check above. Running
`git clone acmeclient-jetkvm-ssh-upload.bundle` directly (skip step 1,
clone the bundle on its own) still fails with `remote did not send all
necessary objects` regardless, since a bundle is never a complete
standalone repo by itself — it always needs to be fetched into an
existing clone that already has the base history. Use Option A if in
doubt.

## Before opening the PR

1. **Hardware validation done (2026-08-11), but not complete — see
   below.** Tested directly against a real JetKVM device over SSH:
   - Confirmed: `/userdata/jetkvm/tls` is the correct storage directory
     for "Custom" TLS mode.
   - Confirmed and **fixed**: the filenames were wrong in the first
     draft. JetKVM's "Custom" TLS mode reads `user-defined.crt` /
     `user-defined.key`, not `fullchain.pem` / `privkey.pem`. The
     script defaults and model/dialog help text now reflect this.
   - Confirmed: JetKVM does not hot-reload a "Custom" certificate; its
     own apply script does a full device `reboot`. The post-upload
     command field's help text says this explicitly; the field is
     still blank by default since a reboot briefly drops any active
     KVM-over-IP session — set it to `reboot` yourself if you want it
     applied automatically.
   - Confirmed and **fixed**: the remote write now stages the cert/key
     under temporary names and atomically `mv`-s them into place,
     instead of truncating the live files in place. Validated
     end-to-end against the device (including cleanup) using throwaway
     filenames — the real device certificates were deliberately never
     touched by this testing.
   - **Not confirmed** (precisely because the real cert files were left
     untouched): that a certificate written to those paths is actually
     *served* after a reboot, and whether "Custom" TLS mode has to be
     manually selected once in the JetKVM web UI first. See
     PR_DESCRIPTION.md's "What this testing did not confirm" for why
     this matters — do a real end-to-end test (deploy, reboot, check
     the served cert in a browser) before merging.
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
