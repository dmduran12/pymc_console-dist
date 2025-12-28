# Installing pyMC Console UI

This guide covers standalone UI installation. For full pyMC Console with manage.sh installer, see [README.md](README.md).

## Quick Install (Standalone UI)

Download and extract the latest release to your pyMC_Repeater's web directory:

```bash
# Download the latest release
cd /tmp
wget https://github.com/dmduran12/pymc_console/releases/latest/download/pymc-ui-latest.tar.gz

# Extract to pyMC_Repeater's web directory
sudo mkdir -p /opt/pymc_repeater/repeater/web/html
sudo tar -xzf pymc-ui-latest.tar.gz -C /opt/pymc_repeater/repeater/web/html/

# Set proper permissions
sudo chown -R repeater:repeater /opt/pymc_repeater/repeater/web/html

# Clean up
rm pymc-ui-latest.tar.gz
```

The dashboard will be served at `http://<your-pi-ip>:8000/`

---

## Quick Update

To update an existing installation to the latest version:

```bash
# Download latest version
cd /tmp
wget https://github.com/dmduran12/pymc_console/releases/latest/download/pymc-ui-latest.tar.gz

# Backup and update
sudo cp -r /opt/pymc_repeater/repeater/web/html /opt/pymc_repeater/repeater/web/html.backup
sudo rm -rf /opt/pymc_repeater/repeater/web/html/*
sudo tar -xzf pymc-ui-latest.tar.gz -C /opt/pymc_repeater/repeater/web/html/
sudo chown -R repeater:repeater /opt/pymc_repeater/repeater/web/html

# Clean up
rm pymc-ui-latest.tar.gz
```

## Specific Version

To install a specific version:

```bash
# Replace v0.2.0 with desired version
wget https://github.com/dmduran12/pymc_console/releases/download/v0.2.0/pymc-ui-v0.2.0.tar.gz
sudo tar -xzf pymc-ui-v0.2.0.tar.gz -C /opt/pymc_repeater/repeater/web/html/
```

## Using manage.sh (Recommended)

For most users, use the manage.sh installer which handles everything automatically:

```bash
git clone https://github.com/dmduran12/pymc_console.git
cd pymc_console
sudo ./manage.sh install
```
