# Installing pyMC Console

This guide covers **manual** installation of the Console dashboard (without `manage.sh`). For the standard installer workflow, see [README.md](README.md).

## Prerequisite

An existing [pyMC_Repeater](https://github.com/rightup/pyMC_Repeater) installation. The Console dashboard is served by pyMC_Repeater's CherryPy server; installing it on its own does nothing useful.

Verify Repeater is installed:

```bash
ls /opt/pymc_repeater/pyproject.toml
```

---

## Using manage.sh (Recommended)

```bash
git clone https://github.com/dmduran12/pymc_console.git
cd pymc_console
sudo ./manage.sh install
```

This downloads the latest Console release, extracts to `/opt/pymc_console/web/html`, and patches `web.web_path` in `/etc/pymc_repeater/config.yaml`. See [README.md](README.md) for all commands.

---

## Manual Install (no manage.sh)

If you don't want to clone this repo, install the release tarball directly:

```bash
# 1. Download the latest Console release
cd /tmp
wget https://github.com/dmduran12/pymc_console-dist/releases/latest/download/pymc-ui-latest.tar.gz

# 2. Extract to /opt/pymc_console/web/html (the Console install target)
sudo mkdir -p /opt/pymc_console/web/html
sudo tar -xzf pymc-ui-latest.tar.gz -C /opt/pymc_console/web/html/

# 3. Set ownership to the repeater service user
sudo chown -R repeater:repeater /opt/pymc_console

# 4. Point pyMC_Repeater at the dashboard (one-time)
#    Open /etc/pymc_repeater/config.yaml and set:
#      web:
#        web_path: /opt/pymc_console/web/html
#    Or, if you have `yq` installed:
sudo yq -i '.web.web_path = "/opt/pymc_console/web/html"' /etc/pymc_repeater/config.yaml

# 5. Restart the repeater service
sudo systemctl restart pymc-repeater

# 6. Clean up
rm /tmp/pymc-ui-latest.tar.gz
```

The dashboard is now served at `http://<your-pi-ip>:8000/`.

---

## Manual Update

To update an existing Console install without using `manage.sh`:

```bash
# Download latest version
cd /tmp
wget https://github.com/dmduran12/pymc_console-dist/releases/latest/download/pymc-ui-latest.tar.gz

# Backup existing dashboard
sudo cp -r /opt/pymc_console/web/html /opt/pymc_console/web/html.backup

# Replace contents (web_path is preserved since we keep the same directory)
sudo rm -rf /opt/pymc_console/web/html/*
sudo tar -xzf pymc-ui-latest.tar.gz -C /opt/pymc_console/web/html/
sudo chown -R repeater:repeater /opt/pymc_console

# Clean up
rm /tmp/pymc-ui-latest.tar.gz
```

No service restart is required for asset-only updates — clients will pick up the new bundle on next page load. Hard-refresh (`Cmd+Shift+R` / `Ctrl+Shift+R`) if stale.

---

## Specific Version

To install a specific version:

```bash
# Replace v0.10.0 with the desired version tag
wget https://github.com/dmduran12/pymc_console-dist/releases/download/v0.10.0/pymc-ui-v0.10.0.tar.gz
sudo rm -rf /opt/pymc_console/web/html/*
sudo tar -xzf pymc-ui-v0.10.0.tar.gz -C /opt/pymc_console/web/html/
sudo chown -R repeater:repeater /opt/pymc_console
```

---

## Uninstall

```bash
sudo rm -rf /opt/pymc_console
# Optional: unset web.web_path in /etc/pymc_repeater/config.yaml to fall back to upstream's Vue.js dashboard.
sudo systemctl restart pymc-repeater
```

pyMC_Repeater itself is not affected.
