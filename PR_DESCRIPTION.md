# security/acme-client: add JetKVM automation via acme.sh deploy hook

**Important notices**

- [x] I have read the contributing guidelines at https://github.com/opnsense/plugins/blob/master/CONTRIBUTING.md
- [x] I opened an issue first for non-trivial changes and linked it below.
- [x] AI tools were used to create at least part of the code submitted herewith.

If AI was used, please disclose:

- **Model used:** Claude (Anthropic), primarily Claude Sonnet 5 across
  several agentic coding sessions (Claude Code).
- **Extent of AI involvement:** Effectively all of the code, this PR
  description, and the commit message were produced by Claude operating
  largely autonomously under a human maintainer's direction and review.
  This included direct SSH access (granted by the maintainer) to a real
  JetKVM device and to a live OPNsense 26.7 test system, used to validate
  this automation end-to-end before opening this PR.

**Related issue:** #5622 (tracks this follow-up, opened when
opnsense/plugins#5621 was closed).

---

## Background

This replaces [opnsense/plugins#5621](https://github.com/opnsense/plugins/pull/5621),
which proposed a full custom PHP implementation (its own SSH exec session,
atomic-write logic, API controller, configd actions) directly in this
plugin. The maintainer closed that PR and asked for the SSH/upload logic
to live in an acme.sh deploy hook instead, with only minimal glue code
here:

> This PR suggests to add all the code/logic to the Acme Client plugin. A
> better approach would be to add a new deploy hook to acme.sh. Then this
> new deploy hook could be utilized by the Acme Client plugin with minimal
> code. This would lower the (code) maintenance burden.

[acmesh-official/acme.sh#7254](https://github.com/acmesh-official/acme.sh/pull/7254)
adds that hook (`deploy/jetkvm.sh`). This PR is the "much smaller
follow-up" the maintainer asked for.

## Summary

Adds a new automation ("Run acme.sh Deploy Hook" type) to the OPNsense
**ACME Client** plugin: **"Upload certificate to JetKVM (SSH)"**
(`acme_jetkvm`).

It's a thin wrapper, `AcmeJetkvm.php` (48 lines), following the exact
pattern already used by `AcmeFritzbox`/`AcmePanos`/`AcmeZyxelGs1900`/etc:
set a few `DEPLOY_JETKVM_*` environment variables from the automation's
config fields and let `LeAutomation\Base::runAcme()` invoke
`acme.sh --deploy --deploy-hook jetkvm`. All of the SSH exec session,
atomic-write logic, and the HTTPS-mode precondition check now live once
in the acme.sh hook, not duplicated here.

Exposed fields: host, username (default `root`), port (default `22`),
and a "Reboot After Upload" checkbox (default checked) mapping to the
hook's `DEPLOY_JETKVM_RESTART_CMD` (`reboot`/`none`). Everything else
(remote path, filenames, permissions, the HTTPS-mode check) uses the
hook's own defaults. Unlike the SFTP/remote-SSH automations, this one
does not use the plugin's managed SSH identity/`known_hosts` store —
acme.sh's own deploy hooks assume SSH access is already configured on
the host, same as every other `Acme*` automation in this plugin.

## Testing done

- `php -l` clean on the new class; `xmllint --noout` clean on the
  changed XML files.
- Manual trace of `LeAutomationFactory`'s type-to-classname derivation
  confirms `acme_jetkvm` resolves to `AcmeJetkvm`.
- **Validated end-to-end on a real OPNsense 26.7 box against a real
  JetKVM device:** locally-built test packages (`os-acme-client` +
  `acme.sh`, each adding only the JetKVM-related file(s) on top of the
  currently published packages — see `pkg-test/` in the delivery repo)
  were installed so this automation could invoke a real
  `deploy/jetkvm.sh`. Confirmed working end to end: issuance → this
  automation → the acme.sh hook → upload → HTTPS-mode check → reboot →
  certificate served by the device. This exercised the happy path
  (device already in Custom mode, reboot enabled); the
  checkbox-unchecked → `none` path and the mode-check-failure path have
  not been run through the plugin itself.
- Not yet testable against a *stock* OPNsense install, since that still
  requires acme.sh#7254 to merge and the FreeBSD acme.sh port to pick it
  up.

## Known open item

`acme_jetkvm_host` has no required-field validation (`Required N`, no
default) and `AcmeJetkvm.php` does not check for an empty host before
invoking the hook. A blank host silently falls back to `jetkvm.sh`'s own
default (the certificate's own domain name) rather than producing a
clear configuration error. Worth deciding before merge whether to mark
the field `Required Y`.

## How to use once merged

1. **Required:** on the JetKVM device's web UI (Settings > Network), set
   **"HTTPS Mode"** to **"Custom"**. This automation does not switch
   HTTPS mode for you.
2. Ensure the firewall's root SSH key is already trusted by the device
   (JetKVM: Settings > Advanced > Developer Mode > paste the public key).
3. In **Services > ACME Client > Automations**, add a new automation and
   select **"Upload certificate to JetKVM (SSH)"**.
4. Fill in the JetKVM host/IP (user defaults to `root`).
5. "Reboot After Upload" defaults to checked, since JetKVM requires a
   full reboot to apply a new "Custom" certificate. Uncheck to
   apply/verify manually instead.
6. Attach the automation to a certificate's "Automations" list.

## Research sources

- [opnsense/plugins#5621](https://github.com/opnsense/plugins/pull/5621) — the original, closed PR, with the full hardware-validation writeup this one builds on.
- [acmesh-official/acme.sh#7254](https://github.com/acmesh-official/acme.sh/pull/7254) — the deploy hook this automation invokes.

---

*See the AI-disclosure notice at the top of this description, and
`APPLY_INSTRUCTIONS.md` in this delivery for how the branch/commit were
prepared and pushed.*
