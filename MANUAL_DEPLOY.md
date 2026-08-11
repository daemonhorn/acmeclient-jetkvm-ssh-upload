# Manually applying this to a live OPNsense instance

This lets you test the JetKVM SSH-upload automation on a real OPNsense box
*before* the acme-client plugin (PR
[opnsense/plugins#5621](https://github.com/opnsense/plugins/pull/5621)) is
merged and released as an actual package update. It copies the 7
changed/new application files directly onto the running system, bypassing
`pkg`.

**Prerequisite:** the ACME Client plugin (`os-acme-client`, currently 4.16)
must already be installed via the normal OPNsense plugin manager
(**System > Firmware > Plugins**). This only overlays the JetKVM automation
changes on top of that installation — it doesn't install the plugin itself.

## What's in `deploy/`

`deploy/usr/local/opnsense/...` mirrors the exact destination paths on an
OPNsense system (OPNsense's package layout installs a plugin's `src/opnsense/`
tree straight to `/usr/local/opnsense/`, confirmed against
`Mk/plugins.mk`'s `install:` target in the `opnsense/plugins` repo). Two are
brand new files, five are modified copies of files that already exist from
the plugin's installed 4.16 release:

| File | Status |
|---|---|
| `mvc/app/controllers/OPNsense/AcmeClient/Api/ActionsController.php` | modified |
| `mvc/app/controllers/OPNsense/AcmeClient/forms/dialogAction.xml` | modified |
| `mvc/app/library/OPNsense/AcmeClient/LeAutomation/ConfigdUploadJetkvm.php` | **new** |
| `mvc/app/models/OPNsense/AcmeClient/AcmeClient.xml` | modified |
| `mvc/app/views/OPNsense/AcmeClient/actions.volt` | modified |
| `scripts/OPNsense/AcmeClient/upload_jetkvm.php` | **new**, mode 0755 |
| `service/conf/actions.d/actions_acmeclient.conf` | modified |

All 7 must be applied together — the dialog references model fields that
must exist, the model's automation type references the automation class,
`actions.volt` calls the new API controller actions, and `actions_acmeclient.conf`
declares the configd actions the script implements.

## 1. Copy the files to the firewall

From a machine with this repo, replace `<opnsense-host>` with your
firewall's address (adjust the SSH user if you don't use `root`):

```sh
rsync -av deploy/usr/local/ root@<opnsense-host>:/usr/local/
```

Or, without rsync, plain `scp` (run from the repo root):

```sh
scp -r deploy/usr/local/opnsense root@<opnsense-host>:/tmp/acmeclient-jetkvm-deploy
ssh root@<opnsense-host> 'cp -Rp /tmp/acmeclient-jetkvm-deploy/* /usr/local/opnsense/ && rm -rf /tmp/acmeclient-jetkvm-deploy'
```

Either way, permissions in `deploy/` are already set correctly
(`upload_jetkvm.php` is `0755`, everything else `0644`) and are preserved by
both `rsync -a` and `cp -p`.

## 2. Back up what you're about to overwrite (recommended)

Before copying, on the firewall itself:

```sh
mkdir -p /root/acmeclient-jetkvm-backup
for f in \
  mvc/app/controllers/OPNsense/AcmeClient/Api/ActionsController.php \
  mvc/app/controllers/OPNsense/AcmeClient/forms/dialogAction.xml \
  mvc/app/models/OPNsense/AcmeClient/AcmeClient.xml \
  mvc/app/views/OPNsense/AcmeClient/actions.volt \
  service/conf/actions.d/actions_acmeclient.conf; do
    mkdir -p "/root/acmeclient-jetkvm-backup/$(dirname "$f")"
    cp "/usr/local/opnsense/$f" "/root/acmeclient-jetkvm-backup/$f"
done
```

(The two *new* files have no prior version to back up — to roll those back
later, just `rm` them; see "Rolling back" below.)

## 3. Restart the affected services

On the firewall, after the files are in place:

```sh
service configd restart     # picks up the new actions in actions_acmeclient.conf
configctl webgui restart    # picks up the PHP/XML/volt changes (drops your GUI session briefly)
```

Note it's `service configd restart` (the plain FreeBSD rc.d command), **not**
`configctl configd restart`. configd exposes its own actions over the same
socket `configctl` normally talks to (`configd actions` / `configd
environment` / `configd lookup`), but there is no `configd restart` action —
`configctl configd restart` fails immediately with `Action not allowed or
missing` before it ever touches your deployed files, since it never reaches
the daemon's config-reload code at all. configd has to be restarted the
ordinary way, like any other rc.d service, because it can't service a
request to kill/replace itself through its own request-handling loop.

`configctl webgui restart` (that one *is* a real configd action, unlike the
line above) will disconnect your current web UI session for a few seconds —
that's expected, just log back in.

To confirm configd actually reloaded and picked up the 3 new actions:

```sh
configctl configd actions | grep -i jetkvm
```

You should see `acmeclient upload-jetkvm`, `acmeclient test-jetkvm-connection`,
and `acmeclient show-jetkvm-identity` in the output.

## 4. Verify

```sh
php -l /usr/local/opnsense/scripts/OPNsense/AcmeClient/upload_jetkvm.php
php -l /usr/local/opnsense/mvc/app/library/OPNsense/AcmeClient/LeAutomation/ConfigdUploadJetkvm.php
php -l /usr/local/opnsense/mvc/app/controllers/OPNsense/AcmeClient/Api/ActionsController.php
ls -la /usr/local/opnsense/scripts/OPNsense/AcmeClient/upload_jetkvm.php   # should be -rwxr-xr-x
```

Then in the GUI: **Services > ACME Client > Automations > Add**, set "Run
Command" — **"Upload certificate to JetKVM (SSH)"** should now be an option.
The new field group (host, port, host key, identity type, remote path,
filenames, chmod, post-upload command) should appear when it's selected.

You can also exercise the backend script directly over SSH on the firewall,
without going through the GUI, e.g.:

```sh
/usr/local/opnsense/scripts/OPNsense/AcmeClient/upload_jetkvm.php --log \
  --identity-type=ecdsa show-identity
```

## Rolling back

```sh
# restore the 5 modified files from your backup
cp -Rp /root/acmeclient-jetkvm-backup/* /usr/local/opnsense/

# remove the 2 new files
rm /usr/local/opnsense/mvc/app/library/OPNsense/AcmeClient/LeAutomation/ConfigdUploadJetkvm.php
rm /usr/local/opnsense/scripts/OPNsense/AcmeClient/upload_jetkvm.php

service configd restart
configctl webgui restart
```

Or simplest: reinstall the `os-acme-client` package from **System >
Firmware > Plugins** to restore the stock 4.16 files, then repeat steps 1-3
here if you want to try again.

## Notes / caveats carried over from the PR

- This deploys the *application* files only — it does not touch the
  `Makefile`/`pkg-descr` package metadata (those only matter for building
  the actual FreeBSD package) or bump the installed plugin's recorded
  version, so the Firmware plugin list will keep showing 4.16 with a
  manually-patched 4.17-worth of files underneath. That's fine for testing;
  it just means `pkg` won't know about this until the real package ships.
- See `PR_DESCRIPTION.md`'s "Hardware validation" section for what has and
  hasn't been confirmed against real JetKVM hardware — in particular,
  whether "Custom" TLS mode needs to be enabled once via the JetKVM web UI
  before it will pick up an uploaded certificate is still unconfirmed.
