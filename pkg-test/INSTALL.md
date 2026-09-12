# Local test packages: JetKVM SSH deploy hook

These are locally-built, deliberately-lower-versioned `.pkg` files for
testing the *combined* acme.sh + ACME Client plugin changes on a real
OPNsense 26.7 box, before either upstream PR merges. **Not official
releases** -- see "How these were built" below for exactly what's
different from the real packages and how that was verified.

| File | Replaces | Real (production) version | This test build |
|---|---|---|---|
| `os-acme-client-4.16_0.pkg` | `os-acme-client` | `4.16_1` | `4.16_0` |
| `acme.sh-3.1.3.99.pkg` | `acme.sh` | `3.1.4` | `3.1.3.99` |

Both test versions are **deliberately lower** than what's currently
published, on purpose: it means a plain `pkg upgrade` (or the real fix
landing later) supersedes these test builds automatically, with no
special-casing needed to get back to normal. See "Reverting" below.

## What's actually different

- **`os-acme-client`**: adds one new automation, "Upload certificate to
  JetKVM (SSH)" (`acme_jetkvm`) -- 1 new file
  (`LeAutomation/AcmeJetkvm.php`, ~15 lines) plus additions to the model
  (`AcmeClient.xml`) and dialog (`dialogAction.xml`). Nothing else in
  the package was touched -- confirmed by diffing the full manifest
  against the real `4.16_1` package field-by-field (scripts, deps, all
  other files: byte-identical).
- **`acme.sh`**: adds exactly one new file,
  `/usr/local/share/examples/acme.sh/deploy/jetkvm.sh` (the deploy hook
  from [acmesh-official/acme.sh#7254](https://github.com/acmesh-official/acme.sh/pull/7254),
  already validated against your real JetKVM device). Nothing else in
  the package was touched -- confirmed the same way (users/groups/
  scripts/directories/all other files: byte-identical to the real
  `3.1.4` package).

## Prerequisites

- `os-acme-client` (any version) already installed via the normal
  plugin manager, since this only overlays it.
- The JetKVM device already has "HTTPS Mode" set to "Custom" and your
  firewall's root SSH key already trusted by the device (same
  prerequisites as the standalone hardware test in `../hardware-test/`).

## Installing

Copy both files to the firewall and install with `pkg add -f` (force,
since both packages are already "installed" at a different version):

```sh
scp os-acme-client-4.16_0.pkg acme.sh-3.1.3.99.pkg root@<opnsense-host>:/tmp/
ssh root@<opnsense-host>
pkg add -f /tmp/os-acme-client-4.16_0.pkg
pkg add -f /tmp/acme.sh-3.1.3.99.pkg
```

`pkg add`'s own post-install scripts handle restarting `configd` and
reloading the webgui template automatically (same as a normal plugin
install) -- no manual restart needed.

**Verify:**

```sh
pkg info os-acme-client acme.sh   # should show 4.16_0 and 3.1.3.99
ls -la /usr/local/share/examples/acme.sh/deploy/jetkvm.sh   # should exist, mode 555
```

Then in the GUI: **Services > ACME Client > Automations > Add** --
"Upload certificate to JetKVM (SSH)" should now be an option, with
Host / Username / SSH Port / "Reboot After Upload" fields.

## Testing

1. Add a new automation, type "Upload certificate to JetKVM (SSH)",
   fill in the device's host/IP.
2. Attach it to a certificate's Automations list, then trigger a
   renewal (or use the certificate's "Rerun automations" action if
   available) to run it for real.
3. Check **Services > ACME Client > Log File** for the
   `acme_jetkvm`/`jetkvm.sh` output -- this is also where the new
   HTTPS-Mode precondition check's error would appear if "Custom" mode
   isn't set on the device (the GUI itself only shows a generic
   "automation failed").

## Reverting

Since both test versions are lower than what's actually published,
either of these gets you back to normal:

```sh
pkg upgrade os-acme-client acme.sh          # normal path, once you're done testing
# or, to force it back immediately regardless of version comparison:
pkg install -f os-acme-client acme.sh
```

Once the real fixes ship (acme.sh#7254 merges and the FreeBSD port
picks it up; the follow-up minimal OPNsense PR merges and releases),
the exact same `pkg upgrade` will pick those up too -- no cleanup step
tied to this test build is needed either way.

## How these were built and verified

Both `.pkg` files were built by downloading the *real*, currently-
published packages directly from `pkg.opnsense.org`
(`FreeBSD:15:amd64/26.7/latest/All/`), patching in only the specific
changed/added files, and repackaging -- not built via the OPNsense/
FreeBSD ports toolchain (not available in the environment that
prepared this).

Verification performed on both packages before use:
- Full round-trip: fresh extraction of the rebuilt `.pkg`, then every
  file's SHA-256 recomputed and compared against the value recorded in
  its own `+MANIFEST` (the same check `pkg install` does before trusting
  package content).
- Field-by-field diff of the full manifest (scripts, lua_scripts,
  directories, users/groups, deps, annotations) against the pristine
  original -- confirmed nothing outside the intended file list changed.
- `xmllint --noout` / `php -l` / `shellcheck` on the actual changed
  files as installed in the package tree.
- Every changed/added file's content hash cross-checked against the
  corresponding file in this repo (`../plugins` branch checkout /
  `../hardware-test/jetkvm.sh`) that was already hardware-validated
  against your real JetKVM device.

`CHECKSUMS.sha256` in this directory has the SHA-256 of the two `.pkg`
files themselves, for your own reference.
