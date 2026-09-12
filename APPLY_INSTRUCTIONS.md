# How to apply this and open the PR

The current design is a single commit,
**`9043168d0` "security/acme-client: add JetKVM automation via acme.sh
deploy hook"**, on branch `feature/acme-jetkvm-deploy-hook` at
`daemonhorn/plugins` (already pushed to that fork). **No PR has been
opened against `opnsense/plugins` yet** — this replaces the earlier
[opnsense/plugins#5621](https://github.com/opnsense/plugins/pull/5621),
which the maintainer closed in favor of this smaller design (see
`PR_DESCRIPTION.md` for the full background).

## Option A: apply the patch file (recommended)

```sh
git clone https://github.com/<your-fork>/plugins.git
cd plugins
git checkout -b feature/acme-jetkvm-deploy-hook master
git am 0001-security-acme-client-add-JetKVM-automation-via-acme.patch
git push origin feature/acme-jetkvm-deploy-hook
```

## Option B: fetch from the bundle

```sh
git clone https://github.com/<your-fork>/plugins.git
cd plugins
git fetch acmeclient-jetkvm-deploy-hook.bundle \
  feature/acme-jetkvm-deploy-hook:feature/acme-jetkvm-deploy-hook
git checkout feature/acme-jetkvm-deploy-hook
git push origin feature/acme-jetkvm-deploy-hook
```

This bundle is a delta against upstream `opnsense/plugins` `master` (as
of the fork's last sync) — step 1 must be a real, non-shallow, non-blob-filtered
clone so that base history is actually present locally.

## Before opening a PR

1. Fill in `security/acme-client/pkg-descr`'s changelog placeholder
   (`#XXXX`) with the real PR number once GitHub assigns one.
2. Open the PR against `opnsense/plugins` (base: `master`) using the
   title and body in `PR_DESCRIPTION.md`.

## Files in this delivery

- `0001-security-acme-client-add-JetKVM-automation-via-acme.patch` — the
  change as a single `git am`-able patch.
- `acmeclient-jetkvm-deploy-hook.bundle` — the same commit as a git
  bundle (alternate way to pull it in).
- `PR_DESCRIPTION.md` — the actual PR title/body (including the required
  AI-disclosure notice).
- `APPLY_INSTRUCTIONS.md` — this file.
- `MANUAL_DEPLOY.md` + `deploy/` — a separate path for testing the
  change directly on a live OPNsense box without waiting for a PR to
  merge (requires `deploy/jetkvm.sh` from
  [acme.sh#7254](https://github.com/acmesh-official/acme.sh/pull/7254)
  to also be present — see `pkg-test/` for a combined test build of
  both halves).
