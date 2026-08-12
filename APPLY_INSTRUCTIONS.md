# How to apply this and open the PR

This delivery is already open as **[opnsense/plugins#5621](https://github.com/opnsense/plugins/pull/5621)**
(branch `feature/acmeclient-jetkvm-ssh-upload` on `daemonhorn/plugins`). The
instructions below are for reproducing/re-applying it elsewhere (a fresh
fork, a different machine) if needed — not a first-time setup.

It's 3 commits, not 1: the original change, a follow-up filling in the real
PR number in the changelog, and a follow-up (driven by real production
testing) fixing the post-upload command's default and documenting a
required device-side prerequisite. Both options below apply all 3, in
order, and are verified working (2026-08-11) against the current
`opnsense/plugins` `master`.

## Option A: apply the patch files (recommended)

```sh
git clone https://github.com/<your-fork>/plugins.git
cd plugins
git checkout -b feature/acmeclient-jetkvm-ssh-upload master
git am 0001-*.patch 0002-*.patch 0003-*.patch
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
`git rev-list --objects --missing=print <ref>` (0 of ~9,860 objects
missing) — **as long as step 1 is a real `git clone` of the actual
repo** (not the bundle itself, and not a partial/blob-filtered clone,
which can silently backfill missing blobs from GitHub and mask a
genuinely incomplete bundle). Running `git clone
acmeclient-jetkvm-ssh-upload.bundle` directly (skip step 1, clone the
bundle on its own) still fails with `remote did not send all necessary
objects` regardless, since a bundle is never a complete standalone repo
by itself — it always needs to be fetched into an existing clone that
already has the base history. Use Option A if in doubt.

## Hardware validation status (as of 2026-08-11, 2nd round)

Both open questions from the first round of hardware testing have since
been closed out by real production use (see PR_DESCRIPTION.md's "Hardware
validation" section for full detail):

- **Confirmed:** a certificate uploaded to `user-defined.crt` /
  `user-defined.key` and applied via reboot *is* served by the device's
  HTTPS listener.
- **Confirmed:** JetKVM's "HTTPS Mode" must already be set to "Custom" in
  the device's own web UI (Settings > Network) — this automation does not
  switch modes for you. Documented in the "JetKVM Host" field's help text
  and step 1 of PR_DESCRIPTION.md's "How to use once merged".
- **Changed:** the post-upload command now defaults to `reboot` instead of
  blank, since this automation is meant to run unattended (cron-driven
  ACME renewal, typically overnight) and a blank default meant a renewed
  certificate never actually got applied without manual follow-up.

## Before opening a PR (if reproducing this elsewhere)

1. Replace the changelog placeholder in `security/acme-client/pkg-descr`
   with the real PR number once GitHub assigns one — this is the
   convention used throughout that file's changelog. (Already done here:
   `#5621`.)
2. Fill in the PR template's checklist (`.github/pull_request_template.md`
   in `opnsense/plugins`) — notably the AI-tools disclosure, which is
   required per that repo's `CONTRIBUTING.md`. `PR_DESCRIPTION.md` already
   includes this at the top, matching the template's format.
3. Open the PR against `opnsense/plugins` (base: `master`) using the title
   and body in `PR_DESCRIPTION.md`.

## Files in this delivery

- `0001-*.patch`, `0002-*.patch`, `0003-*.patch` — the change as a
  3-commit, `git am`-able patch series (apply in order).
- `acmeclient-jetkvm-ssh-upload.bundle` — the same 3 commits as a git
  bundle (alternate way to pull them in).
- `PR_DESCRIPTION.md` — the actual PR title/body (including the required
  AI-disclosure notice).
- `APPLY_INSTRUCTIONS.md` — this file.
- `MANUAL_DEPLOY.md` + `deploy/` — a separate path for testing the change
  directly on a live OPNsense box without waiting for the PR to merge.
