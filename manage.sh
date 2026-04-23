#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# pyMC Console - Dashboard Manager
# ═══════════════════════════════════════════════════════════════════════════════
#
# SCOPE: Console-only.
#
# This script manages the pyMC Console React dashboard overlay. It does NOT
# install, upgrade, or uninstall pyMC_Repeater itself — that is upstream's job
# (run pyMC_Repeater's own manage.sh for Repeater lifecycle).
#
# WHAT WE DO:
#   • Download and install the Console dashboard into /opt/pymc_console
#   • On fresh install, point the Repeater's web.web_path at our dashboard
#   • On upgrade, refresh dashboard assets while preserving web_path
#   • On uninstall, remove /opt/pymc_console (Repeater is left untouched)
#   • Thin systemctl wrappers for the pymc-repeater service
#
# WHAT WE DO NOT DO (anymore):
#   • Clone, install, upgrade, or uninstall pyMC_Repeater
#   • Radio/GPIO configuration
#   • systemd unit management
#   • Any TUI (whiptail/dialog). All prompts are plain terminal I/O.
#
# REPEATER REFERENCES:
#   • $INSTALL_DIR is referenced only to detect that Repeater is installed
#     (we refuse to install Console without it)
#   • $CONFIG_DIR/config.yaml is patched (web.web_path) on fresh install
#   • $REPEATER_USER:$REPEATER_GROUP is used for ownership of our files
#   • The service name matches upstream's unit
#
# NON-INTERACTIVE MODE:
#   Pass --yes (before the verb) or set ASSUME_YES=1 to auto-confirm prompts.
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repeater paths (read-only for us — used to locate config/user)
INSTALL_DIR="/opt/pymc_repeater"
CONFIG_DIR="/etc/pymc_repeater"
REPEATER_USER="repeater"
REPEATER_GROUP="repeater"

# Console paths (we own these)
CONSOLE_DIR="/opt/pymc_console"
UI_DIR="$CONSOLE_DIR/web/html"

# Service (owned by upstream)
SERVICE_NAME="pymc-repeater"

# Release artifacts
UI_REPO="dmduran12/pymc_console-dist"
UI_RELEASE_URL="https://github.com/${UI_REPO}/releases"
UI_TARBALL="pymc-ui-latest.tar.gz"

# Runtime flags (set by CLI parser). Exported so a re-exec preserves them.
export ASSUME_YES="${ASSUME_YES:-0}"

# ─────────────────────────────────────────────────────────────────────────────
# Terminal Output
# ─────────────────────────────────────────────────────────────────────────────

# Enable colors only when stdout is a TTY and NO_COLOR is unset.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

print_step()    { echo -e "\n${BOLD}${CYAN}[$1/$2]${NC} ${BOLD}$3${NC}"; }
print_success() { echo -e "    ${GREEN}✓${NC} $1"; }
print_error()   { echo -e "    ${RED}✗${NC} ${RED}$1${NC}" >&2; }
print_info()    { echo -e "    ${CYAN}➜${NC} $1"; }
print_warning() { echo -e "    ${YELLOW}⚠${NC} $1"; }

print_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}pyMC Console${NC}"
    echo -e "${DIM}React Dashboard for pyMC_Repeater${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Terminal Prompts (no TUI)
# ─────────────────────────────────────────────────────────────────────────────
#
# prompt_yes_no "question" [default]
#   default: "y" or "n" (default "n"). Honors ASSUME_YES=1.
#   Returns 0 on yes, 1 on no.
prompt_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local prompt_suffix
    local reply

    if [[ "$ASSUME_YES" == "1" ]]; then
        return 0
    fi

    if [[ "$default" == "y" ]]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi

    read -r -p "$(echo -e "    ${CYAN}?${NC} ${question} ${prompt_suffix} ")" reply
    reply="${reply:-$default}"
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *)           return 1 ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Status Helpers
# ─────────────────────────────────────────────────────────────────────────────

repeater_installed() { [[ -d "$INSTALL_DIR" ]] && [[ -f "$INSTALL_DIR/pyproject.toml" ]]; }
console_installed()  { [[ -d "$UI_DIR" ]]; }
service_running()    { systemctl is-active "$SERVICE_NAME" &>/dev/null; }

pip_version() {
    local pkg="$1"
    pip3 show "$pkg" 2>/dev/null | awk '/^Version:/ {print $2; exit}' || true
}

get_repeater_version() {
    local v
    v="$(pip_version pymc-repeater)"
    echo "${v:-unknown}"
}

get_console_version() {
    if [[ -f "$UI_DIR/VERSION" ]]; then
        local v
        v=$(tr -d '[:space:]' < "$UI_DIR/VERSION")
        echo "${v:-unknown}"
    else
        echo "unknown"
    fi
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        print_error "This command requires root. Run: sudo $0 $1"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Dashboard Installation (core)
# ─────────────────────────────────────────────────────────────────────────────

install_dashboard() {
    local config_file="$CONFIG_DIR/config.yaml"
    local temp_file="/tmp/pymc-ui-$$.tar.gz"
    local is_fresh_install=true

    if console_installed; then
        is_fresh_install=false
    fi

    print_info "Downloading dashboard..."
    if ! curl -fsSL -o "$temp_file" "${UI_RELEASE_URL}/latest/download/${UI_TARBALL}"; then
        print_error "Download failed from ${UI_RELEASE_URL}/latest/download/${UI_TARBALL}"
        rm -f "$temp_file"
        return 1
    fi

    rm -rf "$UI_DIR"
    mkdir -p "$UI_DIR"
    tar -xzf "$temp_file" -C "$UI_DIR"
    rm -f "$temp_file"

    chown -R "$REPEATER_USER:$REPEATER_GROUP" "$CONSOLE_DIR" 2>/dev/null || true

    if [[ -f "$config_file" ]] && command -v yq &>/dev/null; then
        yq -i '.web //= {}' "$config_file" 2>/dev/null || true
        if [[ "$is_fresh_install" == true ]]; then
            yq -i ".web.web_path = \"$UI_DIR\"" "$config_file"
            print_success "Dashboard installed (web_path configured)"
        else
            print_success "Dashboard updated (web_path preserved)"
        fi
    else
        print_warning "Could not configure web_path — set web.web_path manually in $config_file"
    fi

    local size
    size=$(du -sh "$UI_DIR" 2>/dev/null | cut -f1)
    print_info "Size: $size"
}

# ─────────────────────────────────────────────────────────────────────────────
# Install
# ─────────────────────────────────────────────────────────────────────────────

do_install() {
    require_root "install" || return 1

    if ! repeater_installed; then
        print_error "pyMC_Repeater is not installed at $INSTALL_DIR"
        echo ""
        echo "    The Console dashboard requires pyMC_Repeater to be installed first."
        echo "    Install it using upstream's manage.sh:"
        echo ""
        echo -e "      ${CYAN}git clone https://github.com/rightup/pyMC_Repeater.git${NC}"
        echo -e "      ${CYAN}cd pyMC_Repeater && sudo ./manage.sh install${NC}"
        echo ""
        return 1
    fi

    if console_installed; then
        if ! prompt_yes_no "Console dashboard already installed at $UI_DIR — reinstall?" "n"; then
            print_info "Install cancelled."
            return 0
        fi
    fi

    print_banner
    echo -e "  ${DIM}Mode: Install Console${NC}"

    print_step 1 1 "Installing dashboard"
    install_dashboard

    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo ""
    echo -e "${GREEN}${BOLD}Console Installed!${NC}"
    echo ""
    echo -e "  ${DIM}Versions:${NC}"
    echo -e "    pyMC Repeater: ${CYAN}$(get_repeater_version)${NC}"
    echo -e "    pyMC Console:  ${CYAN}v$(get_console_version)${NC}"
    echo ""
    echo -e "  Dashboard: ${CYAN}http://${ip:-localhost}:8000/${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Upgrade
# ─────────────────────────────────────────────────────────────────────────────

do_upgrade() {
    require_root "upgrade" || return 1

    if ! repeater_installed; then
        print_error "pyMC_Repeater is not installed. Nothing to upgrade against."
        return 1
    fi

    if ! console_installed; then
        print_error "Console is not installed. Run: sudo $0 install"
        return 1
    fi

    # Self-update pymc_console repo and re-exec.
    # NOTE: this must run in the parent process (no subshell) so that `exec`
    # replaces the running manage.sh instead of just a subshell.
    if [[ -d "$SCRIPT_DIR/.git" ]]; then
        print_info "Checking for pymc_console updates..."
        git config --global --add safe.directory "$SCRIPT_DIR" 2>/dev/null || true

        local local_hash remote_hash
        local_hash=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "")
        git -C "$SCRIPT_DIR" fetch origin 2>/dev/null || true
        remote_hash=$(git -C "$SCRIPT_DIR" rev-parse origin/main 2>/dev/null || echo "")

        if [[ -n "$remote_hash" && "$local_hash" != "$remote_hash" ]]; then
            if git -C "$SCRIPT_DIR" pull --ff-only 2>/dev/null \
                || git -C "$SCRIPT_DIR" reset --hard origin/main 2>/dev/null; then
                print_success "pymc_console updated — restarting..."
                exec "$SCRIPT_DIR/manage.sh" upgrade
            fi
        fi
    fi

    local ui_before ui_after
    ui_before=$(get_console_version)

    print_banner
    echo -e "  ${DIM}Mode: Upgrade Console${NC}"

    print_step 1 1 "Updating dashboard"
    install_dashboard

    ui_after=$(get_console_version)

    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo ""
    echo -e "${GREEN}${BOLD}Upgrade Complete!${NC}"
    echo ""
    echo -e "  ${DIM}Versions:${NC}"
    echo -e "    pyMC Repeater: ${CYAN}$(get_repeater_version)${NC}"
    if [[ "$ui_before" != "$ui_after" ]]; then
        echo -e "    pyMC Console:  ${DIM}v$ui_before${NC} → ${CYAN}v$ui_after${NC}"
    else
        echo -e "    pyMC Console:  ${CYAN}v$ui_after${NC}"
    fi
    echo ""
    echo -e "  Dashboard: ${CYAN}http://${ip:-localhost}:8000/${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Uninstall
# ─────────────────────────────────────────────────────────────────────────────

do_uninstall() {
    require_root "uninstall" || return 1

    local has_console=false
    console_installed && has_console=true

    print_banner
    echo -e "  ${DIM}Detected:${NC}"
    echo -e "    Console:   $([[ "$has_console" == true ]] && echo "${GREEN}found${NC} ($CONSOLE_DIR)" || echo "${DIM}not found${NC}")"
    echo -e "    This repo: ${GREEN}$SCRIPT_DIR${NC}"
    echo ""
    echo -e "  ${DIM}Note: pyMC_Repeater will NOT be touched. Use upstream's manage.sh to remove it.${NC}"
    echo ""

    if [[ "$has_console" == false ]]; then
        print_info "Console is not installed; nothing to remove under $CONSOLE_DIR."
    fi

    local will_remove=""
    [[ "$has_console" == true ]] && will_remove+="  • Console dashboard ($CONSOLE_DIR)\n"
    will_remove+="  • pymc_console repo ($SCRIPT_DIR)"

    echo -e "  Will remove:\n${will_remove}"
    echo ""

    if ! prompt_yes_no "Continue with uninstall?" "n"; then
        print_info "Uninstall cancelled."
        return 0
    fi

    local step=1
    local total=1
    [[ "$has_console" == true ]] && ((total++))

    if [[ "$has_console" == true ]]; then
        print_step $step $total "Removing Console dashboard"
        rm -rf "$CONSOLE_DIR"
        print_success "Removed $CONSOLE_DIR"
        ((step++))
    fi

    print_step $step $total "Scheduling pymc_console repo removal"
    # Sanity guard: only self-delete if the path is non-empty and looks like ours
    if [[ -z "$SCRIPT_DIR" || "$SCRIPT_DIR" == "/" ]]; then
        print_warning "Refusing to self-delete: SCRIPT_DIR is unsafe ($SCRIPT_DIR)"
    elif [[ "$(basename "$SCRIPT_DIR")" != *pymc_console* ]]; then
        print_warning "Refusing to self-delete: $SCRIPT_DIR does not look like a pymc_console checkout"
    else
        echo -e "    ${YELLOW}Will remove $SCRIPT_DIR after script exits${NC}"
        # SC2064: intentional expand-now — we want the current SCRIPT_DIR captured.
        # shellcheck disable=SC2064
        trap "rm -rf '$SCRIPT_DIR'" EXIT
        print_success "Scheduled for removal"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Uninstall Complete${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Service Control
# ─────────────────────────────────────────────────────────────────────────────

do_start() {
    require_root "start" || return 1
    systemctl start "$SERVICE_NAME"
    sleep 1
    if service_running; then
        echo "✓ Service started"
    else
        echo "✗ Service failed to start" >&2
        return 1
    fi
}

do_stop() {
    require_root "stop" || return 1
    systemctl stop "$SERVICE_NAME"
    echo "✓ Service stopped"
}

do_restart() {
    require_root "restart" || return 1
    systemctl restart "$SERVICE_NAME"
    sleep 1
    if service_running; then
        echo "✓ Service restarted"
    else
        echo "✗ Service failed to start" >&2
        return 1
    fi
}

do_status() {
    echo "pyMC Repeater:  $(get_repeater_version)"
    if console_installed; then
        echo "pyMC Console:   v$(get_console_version)"
    else
        echo "pyMC Console:   not installed"
    fi
    echo "Service:        $(service_running && echo "running" || echo "stopped")"
}

do_logs() {
    journalctl -u "$SERVICE_NAME" -f
}

# ─────────────────────────────────────────────────────────────────────────────
# Help / CLI
# ─────────────────────────────────────────────────────────────────────────────

show_help() {
    cat << EOF
pyMC Console — Dashboard Manager

Usage: $0 [--yes] <command>

Commands:
  install        Install the Console dashboard (requires pyMC_Repeater)
  upgrade        Refresh Console dashboard assets (preserves web_path)
  uninstall      Remove Console dashboard and this repo
  start          Start the pymc-repeater service
  stop           Stop the pymc-repeater service
  restart        Restart the pymc-repeater service
  status         Show Repeater + Console versions and service state
  logs           Tail the pymc-repeater service logs
  -h, --help     Show this help

Flags:
  --yes, -y      Auto-confirm all prompts (also: ASSUME_YES=1)

Notes:
  • This script manages the Console dashboard only. pyMC_Repeater itself
    must be installed separately using upstream's manage.sh:
      https://github.com/rightup/pyMC_Repeater

  • Radio/GPIO configuration is handled by pyMC_Repeater, not by this script.
EOF
}

print_deprecated_subcommand() {
    local cmd="$1"
    local arg="$2"
    print_error "\`$cmd $arg\` has been deprecated."
    echo "    The Full Stack / Console-only distinction no longer exists."
    echo "    This script now manages the Console dashboard only."
    echo "    To install or manage pyMC_Repeater, use upstream's manage.sh."
    echo ""
    show_help
}

# Parse global flags (--yes / -y / --no-color) anywhere in the argument list.
_args=()
for arg in "$@"; do
    case "$arg" in
        --yes|-y)    ASSUME_YES=1 ;;
        --no-color)  ;; # already handled via NO_COLOR env if set; accept for symmetry
        *)           _args+=("$arg") ;;
    esac
done
set -- "${_args[@]}"
unset _args

case "${1:-}" in
    -h|--help|"")
        show_help
        ;;
    install)
        case "${2:-}" in
            full|console)
                print_deprecated_subcommand "install" "$2"
                exit 1
                ;;
            "")
                do_install
                ;;
            *)
                print_error "Unknown argument: install $2"
                show_help
                exit 1
                ;;
        esac
        ;;
    upgrade)
        case "${2:-}" in
            full|console)
                print_deprecated_subcommand "upgrade" "$2"
                exit 1
                ;;
            "")
                do_upgrade
                ;;
            *)
                print_error "Unknown argument: upgrade $2"
                show_help
                exit 1
                ;;
        esac
        ;;
    uninstall) do_uninstall ;;
    start)     do_start ;;
    stop)      do_stop ;;
    restart)   do_restart ;;
    status)    do_status ;;
    logs)      do_logs ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
