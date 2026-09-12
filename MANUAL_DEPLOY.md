# Manually applying this to a live OPNsense instance

This lets you test the JetKVM automation on a real OPNsense box *before*
a plugin PR (see `PR_DESCRIPTION.md`) is opened, merged, and released as
an actual package update. It copies the 3 changed/new application files
directly onto the running system, bypassing `pkg`.

**Prerequisites:**
- The ACME Client plugin (`os-acme-client`) must already be installed
  via the normal OPNsense plugin manager (**System > Firmware >
  Plugins**). This only overlays the JetKVM automation on top of that
  installation.
- Since this automation is a thin wrapper around an acme.sh deploy hook,
  `/usr/local/share/examples/acme.sh/deploy/jetkvm.sh` must also already
  be installed (from [acme.sh#7254](https://github.com/acmesh-official/acme.sh/pull/7254),
  not yet merged/released). See `pkg-test/` for locally-built test
  packages that add both halves on top of the currently published
  `os-acme-client` and `acme.sh` packages.

## What's in `deploy/`

`deploy/usr/local/opnsense/...` mirrors the exact destination paths on
an OPNsense system (a plugin's `src/opnsense/` tree installs straight to
`/usr/local/opnsense/`, per `Mk/plugins.mk`'s `install:` target).

| File | Status |
|---|---|
| `mvc/app/controllers/OPNsense/AcmeClient/forms/dialogAction.xml` | modified |
| `mvc/app/library/OPNsense/AcmeClient/LeAutomation/AcmeJetkvm.php` | **new** |
| `mvc/app/models/OPNsense/AcmeClient/AcmeClient.xml` | modified |

All 3 must be applied together — the dialog references model fields
that must exist, and the model's automation type references the
automation class.

## 1. Copy the files to the firewall

From a machine with this repo, replace `<opnsense-host>` with your
firewall's address:

```sh
rsync -av deploy/usr/local/ root@<opnsense-host>:/usr/local/
```

Or, without rsync:

```sh
scp -r deploy/usr/local/opnsense root@<opnsense-host>:/tmp/acmeclient-jetkvm-deploy
ssh root@<opnsense-host> 'cp -Rp /tmp/acmeclient-jetkvm-deploy/* /usr/local/opnsense/ && rm -rf /tmp/acmeclient-jetkvm-deploy'
```

## 2. Back up what you're about to overwrite (recommended)

```sh
mkdir -p /root/acmeclient-jetkvm-backup
for f in \
  mvc/app/controllers/OPNsense/AcmeClient/forms/dialogAction.xml \
  mvc/app/models/OPNsense/AcmeClient/AcmeClient.xml; do
    mkdir -p "/root/acmeclient-jetkvm-backup/$(dirname "$f")"
    cp "/usr/local/opnsense/$f" "/root/acmeclient-jetkvm-backup/$f"
done
```

(`AcmeJetkvm.php` is new — to roll it back later, just `rm` it.)

## 3. Restart the affected service

```sh
configctl webgui restart    # picks up the PHP/XML changes (drops your GUI session briefly)
```

No `configd` restart is needed this time — unlike the old design, this
automation doesn't add any new configd actions.

## 4. Verify

```sh
php -l /usr/local/opnsense/mvc/app/library/OPNsense/AcmeClient/LeAutomation/AcmeJetkvm.php
```

Then in the GUI: **Services > ACME Client > Automations > Add** —
**"Upload certificate to JetKVM (SSH)"** should now be an option, with
Host / Username / SSH Port / "Reboot After Upload" fields.

## Rolling back

```sh
cp -Rp /root/acmeclient-jetkvm-backup/* /usr/local/opnsense/
rm /usr/local/opnsense/mvc/app/library/OPNsense/AcmeClient/LeAutomation/AcmeJetkvm.php
configctl webgui restart
```

Or simplest: reinstall the `os-acme-client` package from **System >
Firmware > Plugins** to restore the stock files.

## Notes / caveats

- **Required on the JetKVM device itself:** "HTTPS Mode" must already
  be set to "Custom" under Settings > Network before this automation's
  uploads take effect.
- `acme_jetkvm_host` currently has no required-field validation — see
  "Known open item" in `PR_DESCRIPTION.md`. Leaving it blank will not
  produce a form error; the deploy hook will instead fall back to the
  certificate's own domain name as the SSH target.
