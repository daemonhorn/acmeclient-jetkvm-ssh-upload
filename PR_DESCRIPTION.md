# security/acme-client: add automation to upload certificate to JetKVM via SSH

## Summary

Adds a new automation ("Run Command" type) to the OPNsense **ACME Client**
plugin: **"Upload certificate to JetKVM (SSH)"**
(`configd_upload_jetkvm`).

It deploys the fullchain certificate and private key for an ACME-issued
certificate to a [JetKVM](https://jetkvm.com) KVM-over-IP device over SSH,
with an optional post-upload command (e.g. to restart/reload a service on
the device). It reuses the plugin's existing SSH key management
(`OPNsense\AcmeClient\SSHKeys`) and shares its identity/`known_hosts` store
with the existing **"Upload certificate via SFTP"** and **"Remote Command
via SSH"** automations — the same SSH keypair generated/managed by the
plugin can be reused across all three.

## Why this approach

JetKVM only supports **key-based SSH authentication** (`root@<device>`,
password logins are disabled), enabled by turning on "Developer Mode" and
pasting a public key into its web UI (Settings > Advanced). This lines up
naturally with how the ACME Client plugin already manages SSH identities
for its SFTP/SSH automations, so this change is additive: it adds one new
automation type alongside the existing ones rather than introducing new
SSH infrastructure.

JetKVM does not currently ship an `scp` binary or SFTP server in its
minimal userspace (unconfirmed either way from public sources), so instead
of reusing the plugin's `SftpClient`/`SftpUploader` (SFTP-based) upload
path, this automation opens a plain SSH exec session and pipes a small
POSIX shell script to the remote `sh` via stdin. That script writes the
certificate and key via `cat > file <<'MARKER'` heredocs (using random,
per-run markers) and applies the configured file permissions, followed by
an optional operator-supplied restart command. This only depends on a
POSIX shell and `cat`/`chmod`/`mkdir` being present, which is a safe
assumption for busybox-class embedded Linux.

## Important caveat — please verify before merging

JetKVM's TLS certificate handling is **not part of its stable/documented
API**. Based on public research (JetKVM's GitHub repo/discussions/issues,
see below) at the time of writing:

- Custom TLS certificates are stored under `/userdata/jetkvm/tls` via an
  internal `CertStore`, in PEM format, referenced internally as
  `"user-defined"`.
- Applying a new certificate currently requires a restart of JetKVM's
  HTTPS listener; there is no documented hot-reload.
- As of GitHub issue
  [jetkvm/kvm#1240](https://github.com/jetkvm/kvm/issues/1240), JetKVM
  does **not yet** expose a documented CLI/API to apply a certificate
  without going through its web UI — users currently report only being
  able to apply a cert by pasting it into the GUI.

Given that, this automation deliberately:
- Defaults the remote path to `/userdata/jetkvm/tls` (documented as the
  storage directory for custom certs) but makes it fully configurable,
  with a help-text warning to verify it against the installed firmware
  version.
- Leaves the post-upload "restart command" field blank by default rather
  than guessing at an undocumented reload mechanism, so the plugin never
  silently no-ops or does something destructive on an assumption that
  turns out to be wrong.

**Recommendation before merging:** verify against a real JetKVM device
(`ssh root@<device> ls -la /userdata/jetkvm/tls` after enabling "Custom"
TLS mode once via the GUI) that this is indeed where/how a firmware
picks up files dropped at that path, and adjust the default path/restart
command guidance in the field help text and `pkg-descr` changelog entry
if needed. I was not able to test against physical JetKVM hardware in
this environment.

## Code review notes (2026-08-10)

A follow-up review against a live clone of `opnsense/plugins` `master`
turned up one design point worth the maintainer's attention, plus
confirmation that several other things some review candidates might
flag are actually inherited, consistent behavior from the sibling
`upload_sftp.php` / `remote_ssh_identity_type` automations (not new
issues introduced by this change):

- **Non-atomic remote write (new, not inherited).** `buildRemoteScript()`
  writes the cert and key with `cat > file <<'MARKER'`, which truncates
  each file in place, under `set -e`. If the SSH session drops between
  the cert write and the key write, the device is left with a mismatched
  (or truncated) cert/key pair for what is the device's own HTTPS
  listener. The SFTP automation doesn't have quite the same failure
  shape. Consider writing to a `.tmp` name per file and `mv`-ing both
  into place only after each write succeeds, so a dropped connection
  can't leave the device with a half-applied certificate.
- The "Select 'none' to use default 'ECDSA'" help text on
  `jetkvm_identity_type` is copied verbatim from `sftp_identity_type` /
  `remote_ssh_identity_type` — confirmed against upstream, not a new
  inconsistency.
- `--no-error` / `--automation-id` not appearing in `upload_jetkvm.php`'s
  own `COMMANDS` option lists is correct: both are handled generically
  by the shared `Utils::runCLIMain()` CLI framework used by all of these
  scripts, not per-command options.
- `commandUpload()`'s "no automations attached to any matched cert ⇒
  exit 0" behavior is copied byte-for-byte from `upload_sftp.php`; it's
  a pre-existing pattern in the plugin, not something new here.
- `git am 0001-security-acme-client-add-automation-to-upload-certif.patch`
  applies cleanly against current `opnsense/plugins` `master`.
- The new/changed XML (`AcmeClient.xml`, `dialogAction.xml`) is
  well-formed, checked with `xmllint --noout` against the full
  post-patch files (not just the diff).
- `php -l` on the two new PHP files could not be re-verified in this
  review's environment (no `php` binary available); this repeats the
  claim from the original "Testing done" section below, which was made
  in a different environment and wasn't independently re-checked here.

## What's included

- **Model** (`AcmeClient.xml`): new `configd_upload_jetkvm` option on the
  automation `type` field, plus 11 new `jetkvm_*` fields (host, port, host
  key, user, identity type, remote path, cert/key filenames, cert/key
  chmod, restart command) — mirroring the existing `sftp_*` /
  `remote_ssh_*` field groups.
- **Dialog** (`dialogAction.xml`): new form fields shown when this
  automation type is selected, with help text covering the JetKVM
  Developer Mode / SSH key setup and the caveat above.
- **Automation class**
  (`LeAutomation/ConfigdUploadJetkvm.php`): thin `prepare()` that invokes
  the new configd action, following the same pattern as
  `ConfigdUploadSftp`/`ConfigdRemoteSsh`.
- **Backend script** (`scripts/OPNsense/AcmeClient/upload_jetkvm.php`):
  new standalone CLI script implementing `upload` / `test-connection` /
  `show-identity`, modeled on `upload_sftp.php` and `run_remote_ssh.php`.
  Includes CLI examples and can be run standalone for testing.
- **configd actions** (`actions_acmeclient.conf`): `upload-jetkvm`,
  `test-jetkvm-connection`, `show-jetkvm-identity`.
- **API controller** (`Api/ActionsController.php`): `jetkvmGetIdentityAction`
  / `jetkvmTestConnectionAction`, wired to the "Show Identity" / "Test
  Connection" buttons in `actions.volt` (same UX as the SFTP/SSH
  automations).
- **Version bump**: `Makefile` 4.16 → 4.17, `pkg-descr` changelog entry
  (issue/PR number placeholder `#XXXX` needs to be filled in once this PR
  is opened).

## Testing done

- `php -l` on every new/changed PHP file.
- XML well-formedness check on the model and dialog XML.
- Manual cross-check that every `jetkvm_*` field referenced in the dialog
  form and in the backend script's `getOptionsById()` exists in the model
  with a matching name (11/11).
- Manual trace of the `type` string (`configd_upload_jetkvm`) through
  `LeAutomationFactory`'s class-name derivation
  (`str_replace(' ', '', ucwords(str_replace(['-','_'], ' ', $type)))`)
  to confirm it resolves to `ConfigdUploadJetkvm`, matching the new class
  file name.
- Manual review of the heredoc-based remote script generation for shell
  quoting / injection issues, and a follow-up defensive pass adding
  filename sanitization (`basename()`) against path traversal in the
  configurable cert/key filename fields, plus a graceful error path
  instead of an uncaught assertion when the remote path is empty.
- **Not done / not possible in this environment:** end-to-end testing
  against a running OPNsense install (this plugin depends on the private
  OPNsense core framework — `OPNsense\Core\Config`, `OPNsense\Trust\Cert`,
  etc. — which isn't available outside a real OPNsense system) or against
  physical JetKVM hardware. Please test on real hardware before merging,
  particularly the default remote path/filenames.

## How to use once merged

1. In **Services > ACME Client > Automations**, add a new automation and
   set "Run Command" to **"Upload certificate to JetKVM (SSH)"**.
2. Click **"Show Identity"** to get the plugin's SSH public key (or reuse
   one already configured for another SFTP/SSH automation).
3. On the JetKVM device: Settings > Advanced > enable **Developer Mode**
   and paste that public key into the SSH key field.
4. Fill in the JetKVM host/IP (user defaults to `root`), click **"Test
   Connection"** to verify SSH connectivity and host key trust.
5. Attach the automation to a certificate's "Automations" list so it runs
   after issuance/renewal.

## Research sources

- [jetkvm/kvm#1240 – Add Support for Generating TLS Certs and Applying
  Them Without GUI](https://github.com/jetkvm/kvm/issues/1240)
- [jetkvm/kvm#612 – Issue trying to add custom certificate to TLS
  settings](https://github.com/jetkvm/kvm/issues/612)
- [jetkvm/kvm discussion #298 – HTTPS and custom
  certificates](https://github.com/jetkvm/kvm/discussions/298)
- [JetKVM Developer Tools docs](https://jetkvm.com/docs/advanced-usage/developing)
- [JetKVM Local Access docs](https://jetkvm.com/docs/networking/local-access)
- `web_tls.go` / DeepWiki summaries of JetKVM's TLS storage
  (`/userdata/jetkvm/tls`, `CertStore`, "user-defined" custom cert mode)

---

*Prepared by Claude (Cowork). No GitHub credentials were available in
the sandbox this was built in, so the branch/commit was prepared locally
for you to push — see `APPLY_INSTRUCTIONS.md` in this delivery.*
