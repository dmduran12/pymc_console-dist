# pyMC Console

[![GitHub Release](https://img.shields.io/github/v/release/dmduran12/pymc_console-dist)](https://github.com/dmduran12/pymc_console-dist/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A modern web dashboard for monitoring and managing your [MeshCore](https://meshcore.co.uk/) LoRa mesh repeater.

Built on [pyMC_Repeater](https://github.com/rightup/pyMC_Repeater) by [RightUp](https://github.com/rightup), pyMC Console provides real-time visibility into your mesh network with an intuitive, feature-rich interface.

## How It All Fits Together

The MeshCore Python ecosystem has three components:

```
┌─────────────────────────────────────────────────────────────┐
│                      pyMC Console                           │
│            (this repo - web dashboard UI)                   │
│                                                             │
│  • React dashboard served on port 8000                      │
│  • Visualizes packets, topology, stats                      │
│  • manage.sh installer handles everything                   │
└─────────────────────┬───────────────────────────────────────┘
                      │ uses API from
┌─────────────────────▼───────────────────────────────────────┐
│                    pyMC_Repeater                            │
│           (RightUp's repeater daemon)                       │
│                                                             │
│  • Python daemon that runs the repeater                     │
│  • Provides REST API on port 8000                           │
│  • Handles packet forwarding, logging, config               │
└─────────────────────┬───────────────────────────────────────┘
                      │ built on
┌─────────────────────▼───────────────────────────────────────┐
│                      pyMC_core                              │
│             (RightUp's protocol library)                    │
│                                                             │
│  • Low-level MeshCore protocol implementation               │
│  • Radio drivers (SX1262, SX1276)                           │
│  • Packet encoding/decoding                                 │
└─────────────────────────────────────────────────────────────┘
```

**Key points:**
- **Console does NOT replace Repeater** — they work together
- Console's `manage.sh` installs both Repeater and Console side-by-side
- Console provides the web UI; Repeater provides the backend API and radio control
- You can upgrade Console independently without touching Repeater/Core

## Features

### Dashboard
- **Live packet metrics** — Received, forwarded, dropped packets with sparkline charts
- **TX Delay Recommendations** — Slot-based delay optimization with network role classification (edge/relay/hub/backbone)
- **LBT Insights widgets** — Channel health, collision risk, noise floor, link quality at a glance
- **Time range selector** — View stats from 20 minutes to 7 days
- **Recent packets** — Live feed of incoming traffic

![Dashboard](docs/images/dashboard.png)

### Statistics
- **Airtime utilization** — RX/TX utilization spectrum with peak and mean metrics
- **Link quality polar** — Neighbor signal strength plotted by compass bearing
- **Network composition** — Breakdown of repeaters, companions, and room servers
- **Packet types treemap** — Distribution of ADVERT, TXT_MSG, ACK, RESPONSE, etc.
- **RF noise floor** — Noise floor heatmap showing interference patterns over time
- **Prefix disambiguation** — Health metrics for the topology inference system

![Statistics](docs/images/statistics.png)

### Contacts & Topology
- **Interactive map** — MapLibre GL with dark theme, neighbor positions, and smooth animations
- **Mesh topology graph** — Network connections inferred from packet paths
- **Deep Analysis** — One-click full topology rebuild from 20K+ packets
- **Intelligent disambiguation** — Four-factor scoring resolves prefix collisions
- **Edge confidence** — Line thickness scales with observation count
- **Animated edges** — Trace-in effect on toggle, smooth fade-out
- **Filter toggles** — Solo view for hub nodes or direct neighbors only
- **Loop detection** — Identifies redundant paths (double-line rendering)
- **Visual identity** — Yellow house icon for local node, indigo rings for neighbors
- **Path health panel** — Health scores, weakest links, and latency estimates for observed routes
- **Mobile node detection** — Identifies volatile nodes that appear/disappear frequently
- **Wardriving coverage heatmap** — Overlay coverage data from external wardriving servers (e.g., coverage.wcmesh.com) as a GPU-accelerated heatmap showing signal coverage across your area

![Topology Map](docs/images/topology.png)

### Packets
- **Searchable history** — Filter by type, route, time range
- **Packet details** — Hash, path, payload, signal info, duplicates
- **Path visualization** — Interactive map showing packet route with hop confidence

### Settings
- **Mode toggle** — Forward (repeating) or Monitor (RX only)
- **Duty cycle** — Enable/disable enforcement
- **Radio config** — Live frequency, power, SF, bandwidth changes

![Settings](docs/images/settings.png)

### System & Logs
- **System resources** — 20-minute rolling CPU and memory utilization chart
- **Disk usage** — Storage utilization with progress bar
- **Temperature** — Multi-sensor temperature gauges with threshold coloring
- **Live logs** — Stream from repeater daemon with DEBUG/INFO toggle

![System](docs/images/system.png)

## Quick Start

### Requirements

- Raspberry Pi (3, 4, 5, or Zero 2 W)
- LoRa module (SX1262 or SX1276 based)
- Raspbian/Raspberry Pi OS (Bookworm recommended)

### Installation

```bash
# Clone this repository
git clone https://github.com/dmduran12/pymc_console-dist.git pymc_console
cd pymc_console

# Run the installer (requires sudo)
sudo bash manage.sh install
```

> **⚠️ Important: Branch Selection**
>
> During installation, you'll be asked to select a pyMC_Repeater branch. **Select `feat/dmg`** (the default/recommended option). This branch contains the login/authentication functionality required for the dashboard to work properly.
>
> If you select `dev` or `main`, you may encounter "error 200" or login issues.

The installer will:
1. Install all system dependencies (Python, pip, etc.)
2. Clone and install [pyMC_Repeater](https://github.com/rightup/pyMC_Repeater) as a sibling directory
3. Install [pyMC_core](https://github.com/rightup/pyMC_core) (the protocol library)
4. Deploy the Console web dashboard
5. Configure and start the systemd service

**After installation, your directory structure looks like:**
```
~/pymc_console/       ← Console (this repo)
~/pyMC_Repeater/      ← Repeater daemon (cloned by installer)
/opt/pymc_repeater/   ← Installed repeater files
/opt/pymc_console/    ← Installed console files
```

Once complete, access your dashboard at `http://<your-pi-ip>:8000`

## Management Menu

After installation, run `sudo bash manage.sh` to access the management menu:

```
┌─────────────────────────────────────┐
│     pyMC Console Management         │
├─────────────────────────────────────┤
│  1. Start Service                   │
│  2. Stop Service                    │
│  3. Restart Service                 │
│  4. View Logs                       │
│  5. Configure Radio                 │
│  6. Configure GPIO                  │
│  7. Upgrade                         │
│  8. Uninstall                       │
│  9. Exit                            │
└─────────────────────────────────────┘
```

### Menu Options

- **Start/Stop/Restart** — Control the repeater service
- **View Logs** — Live log output from the repeater
- **Configure Radio** — Set frequency, power, bandwidth, SF via preset selection
- **Configure GPIO** — Set up SPI bus and GPIO pins for your LoRa module
- **Upgrade** — Pull latest updates and reinstall
- **Uninstall** — Remove the installation completely

## Upgrading

To update to the latest version, use the TUI menu:

```bash
cd pymc_console
sudo bash manage.sh
```

Select **Upgrade** and choose:
- **Console UI only** — Updates just the web dashboard (recommended, quick)
- **Full upgrade** — Updates Console + pulls latest pyMC_Repeater/pyMC_core

**Note:** You can safely upgrade Console without affecting your Repeater installation. This is useful when you want new dashboard features but your repeater is running stable.

## Configuration

### Radio Settings

Use the **Configure Radio** menu option, or edit directly:

```bash
sudo nano /etc/pymc_repeater/config.yaml
```

Key settings:
```yaml
radio:
  frequency: 927875000      # Frequency in Hz
  spreading_factor: 7       # SF7-SF12
  bandwidth: 62500          # Bandwidth in Hz  
  tx_power: 28              # TX power in dBm
  coding_rate: 6            # 4/5, 4/6, 4/7, or 4/8
```

### Service Management

```bash
# Check status
sudo systemctl status pymc-repeater

# Start/stop/restart
sudo systemctl start pymc-repeater
sudo systemctl stop pymc-repeater
sudo systemctl restart pymc-repeater

# View live logs
sudo journalctl -u pymc-repeater -f
```

## Hardware Requirements

- **Raspberry Pi** (3, 4, 5, or Zero 2 W recommended)
- **LoRa Module** — SX1262 or SX1276 based (e.g., Waveshare SX1262, LILYGO T3S3)
- **SPI Connection** — Module connected via SPI with GPIO for reset/busy/DIO1

### Tested Modules

- Waveshare SX1262 HAT
- LILYGO T3S3 (via USB serial)
- Ebyte E22 modules
- Heltec LoRa 32

## Troubleshooting

### "Error 200" or Login Issues

This typically means you installed with the wrong pyMC_Repeater branch. The login functionality is only available in the `feat/dmg` branch.

**To fix:**
```bash
cd pymc_console
sudo bash manage.sh upgrade
```

Select **Full pyMC Stack** upgrade and choose the `feat/dmg` branch.

> **Note:** When entering the branch name, use `feat/dmg` (not just `dmg`).

### Service won't start

```bash
# Check for errors
sudo journalctl -u pymc-repeater -n 50

# Verify config syntax
cat /etc/pymc_repeater/config.yaml
```

### No packets being received

1. Verify SPI is enabled: `ls /dev/spidev*`
2. Check GPIO configuration in manage.sh → Configure GPIO
3. Confirm frequency matches your network

### Dashboard not loading

1. Verify service is running: `sudo systemctl status pymc-repeater`
2. Check if port 8000 is accessible: `curl http://localhost:8000/api/stats`

### "Radio presets file not found" warning

This warning during installation is non-fatal. The installer will continue and you can configure radio settings manually. The presets are fetched from an API; if the API is unavailable, common presets are offered as fallback options.

## Uninstalling

```bash
cd pymc_console
sudo bash manage.sh
```

Select **Uninstall** from the menu. This removes:
- `/opt/pymc_repeater` (installation)
- `/etc/pymc_repeater` (configuration)  
- `/var/log/pymc_repeater` (logs)
- The systemd service

## How It Works

### Mesh Topology Analysis

The dashboard reconstructs network topology from packet paths. MeshCore packets contain 2-character hex prefixes representing the route through the mesh:

```
Packet path: ["FA", "79", "24", "19"]
           Origin → Hop1 → Hop2 → Local
```

**The Challenge**: Multiple nodes may share the same 2-char prefix (1 in 256 collision chance). The system uses four-factor scoring inspired by [meshcore-bot](https://github.com/agessaman/meshcore-bot) to resolve ambiguity:

1. **Position (15%)** — Where in paths does this prefix typically appear?
2. **Co-occurrence (15%)** — Which prefixes appear adjacent to this one?
3. **Geographic (35%)** — How close is the candidate to anchor points?
4. **Recency (35%)** — How recently was this node seen?

**Key techniques:**

- **Recency scoring** — Exponential decay `e^(-hours/12)` favors recently-active nodes
- **Age filtering** — Nodes not seen in 14 days are excluded from consideration
- **Dual-hop anchoring** — Candidates scored by distance to both previous and next hops (a relay must be within RF range of both neighbors)
- **Score-weighted redistribution** — Appearance counts redistributed proportionally by combined score
- **Source-geographic correlation** — Position-1 prefixes scored by distance from packet origin

The system loads up to 20,000 packets (~7 days of traffic) to build comprehensive topology evidence.

![Prefix Disambiguation](docs/images/disambiguation.png)

### Edge Rendering

Topology edges are rendered with visual cues indicating confidence:

- **Line thickness** — Scales from 1.5px (5 validations) to 10px (100+ validations)
- **Validation threshold** — Edges require 5+ certain observations to render
- **Certainty conditions** — An edge is "certain" when:
  - Both endpoints have ≥0.6 confidence (HIGH threshold), OR
  - The destination has ≥0.9 confidence (VERY_HIGH threshold), OR
  - It's the last hop to local node
- **Inclusion threshold** — Edges require ≥0.4 confidence (MEDIUM threshold) for topology
- **Trace animation** — Edges "draw" from point A to B when topology is enabled
- **Fade animation** — Edges smoothly fade out when topology is disabled
- **Loop edges** — Redundant paths rendered as parallel double-lines in accent color

### Path Visualization

Clicking a packet shows its route on a map with confidence indicators:

- **Green** — 100% confidence (unique prefix, no collision)
- **Yellow** — 50-99% confidence (high certainty)
- **Orange** — 25-49% confidence (medium certainty)
- **Red** — 1-24% confidence (low certainty)
- **Gray** — Unknown prefix (not in neighbor list)

## License

MIT — See [LICENSE](LICENSE)

## Credits

Built on the excellent work of:

- **[RightUp](https://github.com/rightup)** — Creator of pyMC_Repeater, pymc_core, and the MeshCore ecosystem
- **[pyMC_Repeater](https://github.com/rightup/pyMC_Repeater)** — Core repeater daemon for LoRa communication and mesh routing
- **[pymc_core](https://github.com/rightup/pyMC_core)** — Underlying mesh protocol library
- **[meshcore-bot](https://github.com/agessaman/meshcore-bot)** — Inspiration for recency scoring and dual-hop anchor disambiguation
- **[MeshCore](https://meshcore.co.uk/)** — The MeshCore project and community
