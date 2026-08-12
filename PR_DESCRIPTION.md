# security/acme-client: add automation to upload certificate to JetKVM via SSH

**Important notices**

- [x] I have read the contributing guidelines at https://github.com/opnsense/plugins/blob/master/CONTRIBUTING.md
- [ ] I opened an issue first for non-trivial changes and linked it below.
- [x] AI tools were used to create at least part of the code submitted herewith.

If AI was used, please disclose:

- **Model used:** Claude (Anthropic). Primarily Claude Sonnet 5 across several
  agentic coding sessions (Claude Code); an earlier pass also used Claude
  Opus 5 as an independent advisory reviewer of the code and documentation.
- **Extent of AI involvement:** Effectively all of the code, this PR
  description, and the commit messages were produced by Claude operating
  largely autonomously under a human maintainer's direction and review
  across multiple sessions. This included direct SSH access (granted by the
  maintainer) to a real JetKVM device, and separately to a live OPNsense
  26.7.1_1 test system, to validate assumptions that public documentation
  alone couldn't settle — the exact remote storage path/filenames, the
  reboot-to-apply requirement, and the "HTTPS Mode: Custom" prerequisite —
  and to debug a deployment issue after manual testing surfaced it. No
  GitHub credentials were available in the sandbox the code was originally
  drafted in, so the branch/commits were prepared locally and later
  pushed/opened as this PR, and subsequently revised, by the maintainer's
  AI assistant with their authorization.

*No issue was opened ahead of this PR.* This is an incremental addition to
an existing, actively-maintained plugin (not a new plugin), but happy to
open one retroactively and link it here if maintainers would prefer that.

---

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

## Hardware validation (2026-08-11)

JetKVM's TLS certificate handling is **not part of its stable/documented
API**, so the original draft of this PR was based on public research only
(JetKVM's GitHub repo/discussions/issues, see below) and flagged that as
the biggest open question before merging. That has since been tested
directly against a real JetKVM device over SSH:

- `/userdata/jetkvm/tls` **is** the correct storage directory for
  "Custom" TLS mode — confirmed.
- The filenames were **wrong** in the original draft and have been
  corrected. JetKVM's "Custom" TLS mode reads `user-defined.crt` /
  `user-defined.key` from that directory — not `fullchain.pem` /
  `privkey.pem` as first guessed. (Other filenames present in that same
  directory, e.g. `jetkvm.crt`, back JetKVM's other, non-custom TLS
  modes and are unrelated to "Custom" mode.) The script's defaults and
  the model/dialog help text now use the confirmed names.
- There is indeed no hot-reload: the device's own certificate-apply
  script (`update-user-defined.sh`, shipped in that same directory) does
  a full `sync && reboot` after writing the cert/key. The post-upload
  command field's help text states this explicitly.
- The remote write was changed from truncating the live `cat > file`
  target in place to staging both files under temporary names, chmod'ing
  them, and only `mv`-ing them into their final names (an atomic rename)
  once both are fully written — so a dropped connection or a failed
  write can no longer leave the device with a truncated or mismatched
  cert/key pair for its own HTTPS listener. This exact write sequence
  (staging, chmod, atomic rename, cleanup) was validated end-to-end
  against the device using throwaway filenames.

A follow-up round of testing on production hardware (running this
automation for real, unattended, as part of cron-driven ACME renewal)
closed out both items the first round of hardware validation had left
open:

- **Confirmed: a certificate uploaded to `user-defined.crt` /
  `user-defined.key` and then applied via reboot *is* served** by the
  device's HTTPS listener afterward — verified in a browser against the
  device.
- **Confirmed: JetKVM's "HTTPS Mode" must already be set to "Custom" in
  the device's own web UI (Settings > Network) before this automation's
  uploads take effect.** This automation only writes the cert/key files
  and optionally reboots — it does not switch HTTPS mode for you. The
  "JetKVM Host" field's help text and the "How to use once merged" steps
  below now state this as a required prerequisite rather than a
  should-probably-do-this-anyway suggestion.
- **Changed the post-upload command's default from blank to `reboot`.**
  Leaving it blank meant a certificate renewed by an unattended cron job
  never actually got applied without a human manually rebooting the
  device afterward — which defeats the point of automating renewal in
  the first place. Since these renewals (and the reboot they trigger)
  typically run overnight, when an active KVM-over-IP session is
  unlikely, defaulting to `reboot` is the better tradeoff for this
  automation's real use case; the field can still be cleared for anyone
  who'd rather apply/verify manually.

No further changes to the remote path/filenames are expected to be
needed, though — as the help text still notes — none of this is
documented/stable JetKVM API, so it's worth a spot-check after any
JetKVM firmware upgrade.

## Code review notes (2026-08-10, updated 2026-08-11)

A follow-up review against a live clone of `opnsense/plugins` `master`
turned up one design point, since fixed, plus confirmation that several
other things some review candidates might flag are actually inherited,
consistent behavior from the sibling `upload_sftp.php` /
`remote_ssh_identity_type` automations (not new issues introduced by
this change):

- **Non-atomic remote write — fixed.** `buildRemoteScript()` used to
  write the cert and key with `cat > file <<'MARKER'`, which truncates
  each file in place, under `set -e`. If the SSH session dropped between
  the cert write and the key write, the device would be left with a
  mismatched (or truncated) cert/key pair for what is the device's own
  HTTPS listener — the SFTP automation doesn't have quite the same
  failure shape. Both files are now staged under temporary names,
  chmod'ed, and only `mv`-ed into their final names once both are fully
  written, validated against a real device (see "Hardware validation"
  above).
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
- `php -l` on all three new/changed PHP files (`upload_jetkvm.php`,
  `ConfigdUploadJetkvm.php`, `ActionsController.php`) re-verified with
  an actual `php-cli` (via a disposable container, since this review
  environment has no `php` binary installed) after the atomic-write and
  default-filename fixes — no syntax errors.

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

- `php -l` on every new/changed PHP file, re-verified with a real
  `php-cli` after the latest fixes (see "Code review notes").
- XML well-formedness check (`xmllint --noout`) on the full, post-patch
  model and dialog XML files.
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
- `git am` verified to apply the patch cleanly against current
  `opnsense/plugins` `master`.
- **Real JetKVM hardware (2026-08-11):** connected over SSH and
  confirmed the remote path, corrected the deployed filenames, confirmed
  the reboot-to-apply behavior, and validated the atomic-write sequence
  end-to-end using throwaway filenames (never touching the device's real
  certificate files). See "Hardware validation" above for details.
- **Still not done / not possible in this environment:** end-to-end
  testing against a running OPNsense install (this plugin depends on the
  private OPNsense core framework — `OPNsense\Core\Config`,
  `OPNsense\Trust\Cert`, etc. — which isn't available outside a real
  OPNsense system), i.e. the model/dialog/API-controller wiring and the
  actual ACME-issued-certificate-to-device flow haven't been exercised
  end-to-end, only the underlying SSH/remote-script mechanism against
  the JetKVM side.

## How to use once merged

1. **Required:** on the JetKVM device's web UI, under Settings > Network,
   set **"HTTPS Mode"** to **"Custom"**. This automation only writes the
   `user-defined.crt`/`.key` files (and optionally reboots) — it does not
   switch HTTPS mode for you, and uploads won't take effect until this is
   set. Confirmed on production hardware (see "Hardware validation"
   above).
2. In **Services > ACME Client > Automations**, add a new automation and
   set "Run Command" to **"Upload certificate to JetKVM (SSH)"**.
3. Click **"Show Identity"** to get the plugin's SSH public key (or reuse
   one already configured for another SFTP/SSH automation).
4. On the JetKVM device: Settings > Advanced > enable **Developer Mode**
   and paste that public key into the SSH key field.
5. Fill in the JetKVM host/IP (user defaults to `root`), click **"Test
   Connection"** to verify SSH connectivity and host key trust.
6. The "Post-Upload Command" field defaults to `reboot`, since JetKVM
   requires a full device reboot to pick up a new "Custom" certificate
   and this automation is meant to run unattended. This briefly drops any
   active KVM-over-IP session — clear the field if you'd rather
   apply/verify manually instead.
7. Attach the automation to a certificate's "Automations" list so it runs
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

*See the AI-disclosure notice at the top of this description, and
`APPLY_INSTRUCTIONS.md` in this delivery for how the branch/commits were
prepared and pushed.*
