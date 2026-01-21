#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# pyMC Console - Dashboard Overlay Manager
# ═══════════════════════════════════════════════════════════════════════════════
#
# ARCHITECTURE: Thin wrapper around pyMC_Repeater's native installer.
# We don't duplicate upstream's functionality - we extend it with our dashboard.
#
# WHAT WE DO:
#   • Clone/update pyMC_Repeater (to access their manage.sh)
#   • Call upstream's manage.sh for install/upgrade/uninstall
#   • Overlay our React dashboard after upstream completes
#   • Respect user's UI preference (don't force our dashboard on upgrades)
#
# WHAT UPSTREAM DOES:
#   • User creation, directories, dependencies
#   • pip install (pymc_repeater, pymc_core)
#   • Service file, systemd management
#   • Radio/GPIO configuration
#   • Config file management
#
# DASHBOARD OVERLAY RULES:
#   • Fresh install → Set web.web_path to our dashboard
#   • Upgrade → Update files only, preserve user's web_path choice
#
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLONE_DIR="$(dirname "$SCRIPT_DIR")/pyMC_Repeater"

INSTALL_DIR="/opt/pymc_repeater"
CONSOLE_DIR="/opt/pymc_console"
UI_DIR="$CONSOLE_DIR/web/html"
CONFIG_DIR="/etc/pymc_repeater"

SERVICE_NAME="pymc-repeater"
DEFAULT_BRANCH="dev"

UI_REPO="dmduran12/pymc_console-dist"
UI_RELEASE_URL="https://github.com/${UI_REPO}/releases"

# ─────────────────────────────────────────────────────────────────────────────
# Terminal Output
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

print_step()    { echo -e "\n${BOLD}${CYAN}[$1/$2]${NC} ${BOLD}$3${NC}"; }
print_success() { echo -e "    ${GREEN}✓${NC} $1"; }
print_error()   { echo -e "    ${RED}✗${NC} ${RED}$1${NC}"; }
print_info()    { echo -e "    ${CYAN}➜${NC} $1"; }
print_warning() { echo -e "    ${YELLOW}⚠${NC} $1"; }

print_banner() {
    clear
    echo ""
    echo -e "${BOLD}${CYAN}pyMC Console${NC}"
    echo -e "${DIM}React Dashboard for pyMC_Repeater${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# TUI Setup (whiptail/dialog)
# ─────────────────────────────────────────────────────────────────────────────

setup_dialog() {
    if command -v whiptail &>/dev/null; then
        DIALOG="whiptail"
    elif command -v dialog &>/dev/null; then
        DIALOG="dialog"
    else
        echo "Installing whiptail..."
        apt-get update -qq && apt-get install -y whiptail
        DIALOG="whiptail"
    fi
}

show_info()   { $DIALOG --backtitle "pyMC Console" --title "$1" --msgbox "$2" 12 60; }
show_error()  { $DIALOG --backtitle "pyMC Console" --title "Error" --msgbox "$1" 10 60; }
ask_yes_no()  { $DIALOG --backtitle "pyMC Console" --title "$1" --yesno "$2" 12 60; }

# ─────────────────────────────────────────────────────────────────────────────
# Status Helpers
# ─────────────────────────────────────────────────────────────────────────────

is_installed()    { [[ -d "$INSTALL_DIR" ]] && [[ -f "$INSTALL_DIR/pyproject.toml" ]]; }
service_running() { systemctl is-active "$SERVICE_NAME" &>/dev/null; }

get_version() {
    pip3 show pymc-repeater 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "unknown"
}

get_console_version() {
    [[ -f "$UI_DIR/VERSION" ]] && cat "$UI_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' && return
    echo "unknown"
}

get_core_version() {
    pip3 show pymc-core 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "unknown"
}

get_repeater_version() {
    pip3 show pymc-repeater 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "unknown"
}

print_version_summary() {
    local core_ver=$(get_core_version)
    local rep_ver=$(get_repeater_version)
    local ui_ver=$(get_console_version)
    
    echo ""
    echo -e "  ${DIM}Versions:${NC}"
    echo -e "    pyMC Core:     ${CYAN}$core_ver${NC}"
    echo -e "    pyMC Repeater: ${CYAN}$rep_ver${NC}"
    echo -e "    pyMC Console:  ${CYAN}v$ui_ver${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Git Operations
# ─────────────────────────────────────────────────────────────────────────────

clone_upstream() {
    local branch="$1"
    
    git config --global --add safe.directory "$CLONE_DIR" 2>/dev/null || true
    
    if [[ -d "$CLONE_DIR/.git" ]]; then
        print_info "Updating existing clone..."
        cd "$CLONE_DIR"
        git fetch origin --prune
        git reset --hard HEAD
        git checkout "$branch" 2>/dev/null || git checkout -b "$branch" "origin/$branch"
        git reset --hard "origin/$branch"
    else
        print_info "Cloning pyMC_Repeater@$branch..."
        rm -rf "$CLONE_DIR"
        git clone -b "$branch" "https://github.com/rightup/pyMC_Repeater.git" "$CLONE_DIR"
    fi
    
    # Show what we got
    cd "$CLONE_DIR"
    local commit=$(git rev-parse --short HEAD)
    local date=$(git log -1 --format=%cd --date=short)
    print_success "Source: $branch @ $commit ($date)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Upstream Installer Wrapper
# ─────────────────────────────────────────────────────────────────────────────

run_upstream() {
    local action="$1"
    local upstream_script="$CLONE_DIR/manage.sh"
    
    if [[ ! -f "$upstream_script" ]]; then
        print_error "Upstream manage.sh not found"
        return 1
    fi
    
    echo ""
    echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}Running pyMC_Repeater $action...${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
    echo ""
    
    (cd "$CLONE_DIR" && bash "$upstream_script" "$action")
    local exit_code=$?
    
    echo ""
    echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "pyMC_Repeater $action completed"
        return 0
    else
        print_error "pyMC_Repeater $action failed"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Dashboard Installation
# ─────────────────────────────────────────────────────────────────────────────

install_dashboard() {
    local config_file="$CONFIG_DIR/config.yaml"
    local temp_file="/tmp/pymc-ui-$$.tar.gz"
    local is_fresh_install=true
    
    # Detect fresh install vs upgrade
    if [[ -d "$CONSOLE_DIR" ]]; then
        is_fresh_install=false
    fi
    
    # Download dashboard
    print_info "Downloading dashboard..."
    if ! curl -fsSL -o "$temp_file" "${UI_RELEASE_URL}/latest/download/pymc-ui-latest.tar.gz"; then
        print_error "Download failed"
        rm -f "$temp_file"
        return 1
    fi
    
    # Clean and extract
    rm -rf "$UI_DIR"
    mkdir -p "$UI_DIR"
    tar -xzf "$temp_file" -C "$UI_DIR"
    rm -f "$temp_file"
    
    # Set permissions
    chown -R repeater:repeater "$CONSOLE_DIR" 2>/dev/null || true
    
    # Configure web_path (fresh install only)
    if [[ -f "$config_file" ]] && command -v yq &>/dev/null; then
        # Ensure web section exists
        yq -i '.web //= {}' "$config_file" 2>/dev/null || true
        
        if [[ "$is_fresh_install" == true ]]; then
            yq -i ".web.web_path = \"$UI_DIR\"" "$config_file"
            print_success "Dashboard installed (web_path configured)"
        else
            print_success "Dashboard updated (web_path preserved)"
        fi
    else
        print_warning "Could not configure web_path - set manually in $config_file"
    fi
    
    local size=$(du -sh "$UI_DIR" 2>/dev/null | cut -f1)
    print_info "Size: $size"
}

# ─────────────────────────────────────────────────────────────────────────────
# Install
# ─────────────────────────────────────────────────────────────────────────────

do_install() {
    if [[ "$EUID" -ne 0 ]]; then
        show_error "Installation requires root.\n\nRun: sudo $0 install"
        return 1
    fi
    
    # Check if pyMC_Repeater already installed
    local repeater_exists=false
    is_installed && repeater_exists=true
    
    # Installation type selection (interactive only)
    local install_type="${1:-}"
    if [[ -z "$install_type" ]]; then
        if [[ "$repeater_exists" == true ]]; then
            # Repeater exists - only offer console
            install_type="console"
            show_info "Existing Installation" "pyMC_Repeater detected.\n\nInstalling Console dashboard only."
        else
            # Fresh system - offer choice
            install_type=$($DIALOG --backtitle "pyMC Console" --title "Installation Type" --menu \
                "\nSelect what to install:" 14 55 2 \
                "full"    "Full Stack (pyMC_Repeater + Console)" \
                "console" "Console Only (dashboard for existing install)" \
                3>&1 1>&2 2>&3) || return 0
        fi
    fi
    
    case "$install_type" in
        full)    do_install_full ;;
        console) do_install_console ;;
        *)       show_error "Unknown install type: $install_type"; return 1 ;;
    esac
}

do_install_full() {
    if is_installed; then
        show_error "pyMC_Repeater already installed.\n\nUse 'upgrade' or choose Console-only install."
        return 1
    fi
    
    # Branch selection
    local branch
    branch=$($DIALOG --backtitle "pyMC Console" --title "Select Branch" --menu \
        "\nSelect pyMC_Repeater branch:" 14 50 3 \
        "dev"  "Development (recommended)" \
        "main" "Stable release" \
        "custom" "Enter custom branch" 3>&1 1>&2 2>&3) || return 0
    
    if [[ "$branch" == "custom" ]]; then
        branch=$($DIALOG --backtitle "pyMC Console" --inputbox "Branch name:" 8 40 "dev" 3>&1 1>&2 2>&3) || return 0
    fi
    
    print_banner
    echo -e "  ${DIM}Mode: Full Stack${NC}"
    echo -e "  ${DIM}Branch: $branch${NC}"
    
    # Step 1: Clone upstream
    print_step 1 3 "Preparing pyMC_Repeater"
    clone_upstream "$branch"
    
    # Step 2: Run upstream installer
    print_step 2 3 "Installing pyMC_Repeater"
    run_upstream "install" || return 1
    
    # Step 3: Overlay dashboard
    print_step 3 3 "Installing dashboard"
    install_dashboard
    
    # Done
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo ""
    echo -e "${GREEN}${BOLD}Installation Complete!${NC}"
    print_version_summary
    echo ""
    echo -e "  Dashboard: ${CYAN}http://$ip:8000/${NC}"
    echo ""
    echo -e "  ${DIM}Configure radio: cd $CLONE_DIR && sudo ./manage.sh${NC}"
    echo ""
}

do_install_console() {
    if ! is_installed; then
        show_error "pyMC_Repeater not found.\n\nUse Full Stack install or install pyMC_Repeater first."
        return 1
    fi
    
    if [[ -d "$UI_DIR" ]]; then
        if ! ask_yes_no "Console Exists" "Console dashboard already installed.\n\nReinstall?"; then
            return 0
        fi
    fi
    
    print_banner
    echo -e "  ${DIM}Mode: Console Only${NC}"
    
    # Single step: Install dashboard
    print_step 1 1 "Installing dashboard"
    install_dashboard
    
    # Done
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo ""
    echo -e "${GREEN}${BOLD}Console Installed!${NC}"
    echo ""
    echo -e "  ${DIM}Versions:${NC}"
    echo -e "    pyMC Console:  ${CYAN}v$(get_console_version)${NC}"
    echo ""
    echo -e "  Dashboard: ${CYAN}http://$ip:8000/${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Upgrade
# ─────────────────────────────────────────────────────────────────────────────

do_upgrade() {
    if ! is_installed; then
        show_error "Not installed. Use 'install' first."
        return 1
    fi
    
    if [[ "$EUID" -ne 0 ]]; then
        show_error "Upgrade requires root.\n\nRun: sudo $0 upgrade"
        return 1
    fi
    
    # Self-update pymc_console repo
    if [[ -d "$SCRIPT_DIR/.git" ]]; then
        print_info "Checking for pymc_console updates..."
        cd "$SCRIPT_DIR"
        git config --global --add safe.directory "$SCRIPT_DIR" 2>/dev/null || true
        git fetch origin 2>/dev/null || true
        
        local local_hash=$(git rev-parse HEAD 2>/dev/null)
        local remote_hash=$(git rev-parse origin/main 2>/dev/null)
        
        if [[ -n "$remote_hash" && "$local_hash" != "$remote_hash" ]]; then
            if git pull --ff-only 2>/dev/null || git reset --hard origin/main 2>/dev/null; then
                print_success "pymc_console updated - restarting..."
                exec "$SCRIPT_DIR/manage.sh" upgrade
            fi
        fi
    fi
    
    # Capture current versions before upgrade
    local core_before=$(get_core_version)
    local rep_before=$(get_repeater_version)
    local ui_before=$(get_console_version)
    
    # Get current branch
    local branch="$DEFAULT_BRANCH"
    if [[ -d "$CLONE_DIR/.git" ]]; then
        branch=$(cd "$CLONE_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch="$DEFAULT_BRANCH"
    fi
    
    # Component selection checklist
    local choices
    choices=$($DIALOG --backtitle "pyMC Console" --title "Select Components" \
        --checklist "\nSelect what to upgrade:\n\nYour configuration will be preserved." 14 55 2 \
        "console"  "pyMC Console dashboard" ON \
        "repeater" "pyMC_Repeater ($branch)" ON \
        3>&1 1>&2 2>&3) || return 0
    
    local upgrade_console=false
    local upgrade_repeater=false
    [[ "$choices" == *"console"* ]] && upgrade_console=true
    [[ "$choices" == *"repeater"* ]] && upgrade_repeater=true
    
    # Nothing selected
    if [[ "$upgrade_console" == false && "$upgrade_repeater" == false ]]; then
        show_info "Nothing Selected" "No components selected for upgrade."
        return 0
    fi
    
    print_banner
    
    # Calculate steps
    local step=1
    local total=0
    [[ "$upgrade_repeater" == true ]] && ((total+=2))  # clone + upgrade
    [[ "$upgrade_console" == true ]] && ((total++))
    
    # Upgrade Repeater if selected
    if [[ "$upgrade_repeater" == true ]]; then
        print_step $step $total "Updating pyMC_Repeater source"
        clone_upstream "$branch"
        ((step++))
        
        print_step $step $total "Upgrading pyMC_Repeater"
        run_upstream "upgrade" || return 1
        ((step++))
    fi
    
    # Upgrade Console if selected
    if [[ "$upgrade_console" == true ]]; then
        print_step $step $total "Updating dashboard"
        install_dashboard
    fi
    
    # Done
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    local core_after=$(get_core_version)
    local rep_after=$(get_repeater_version)
    local ui_after=$(get_console_version)
    
    echo ""
    echo -e "${GREEN}${BOLD}Upgrade Complete!${NC}"
    echo ""
    echo -e "  ${DIM}Versions:${NC}"
    [[ "$core_before" != "$core_after" ]] \
        && echo -e "    pyMC Core:     ${DIM}$core_before${NC} → ${CYAN}$core_after${NC}" \
        || echo -e "    pyMC Core:     ${CYAN}$core_after${NC}"
    [[ "$rep_before" != "$rep_after" ]] \
        && echo -e "    pyMC Repeater: ${DIM}$rep_before${NC} → ${CYAN}$rep_after${NC}" \
        || echo -e "    pyMC Repeater: ${CYAN}$rep_after${NC}"
    [[ "$ui_before" != "$ui_after" ]] \
        && echo -e "    pyMC Console:  ${DIM}v$ui_before${NC} → ${CYAN}v$ui_after${NC}" \
        || echo -e "    pyMC Console:  ${CYAN}v$ui_after${NC}"
    echo ""
    echo -e "  Dashboard: ${CYAN}http://$ip:8000/${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Uninstall
# ─────────────────────────────────────────────────────────────────────────────

do_uninstall() {
    # Check if there's anything to uninstall
    local has_repeater=false
    local has_console=false
    local has_clone=false
    local has_self=true  # Script is always running from somewhere
    
    is_installed && has_repeater=true
    [[ -d "$CONSOLE_DIR" ]] && has_console=true
    [[ -d "$CLONE_DIR" ]] && has_clone=true
    
    # Debug: show what we found
    print_banner
    echo -e "  ${DIM}Detected components:${NC}"
    echo -e "    Repeater:  $([[ "$has_repeater" == true ]] && echo "${GREEN}found${NC}" || echo "${DIM}not found${NC}")"
    echo -e "    Console:   $([[ "$has_console" == true ]] && echo "${GREEN}found${NC} ($CONSOLE_DIR)" || echo "${DIM}not found${NC}")"
    echo -e "    Clone:     $([[ "$has_clone" == true ]] && echo "${GREEN}found${NC} ($CLONE_DIR)" || echo "${DIM}not found${NC}")"
    echo -e "    This repo: ${GREEN}$SCRIPT_DIR${NC}"
    echo ""
    
    if [[ "$EUID" -ne 0 ]]; then
        show_error "Uninstall requires root.\n\nRun: sudo $0 uninstall"
        return 1
    fi
    
    # Build description of what will be removed
    local will_remove=""
    [[ "$has_repeater" == true ]] && will_remove+="• pyMC_Repeater\n"
    [[ "$has_console" == true ]] && will_remove+="• Console dashboard ($CONSOLE_DIR)\n"
    [[ "$has_clone" == true ]] && will_remove+="• pyMC_Repeater clone ($CLONE_DIR)\n"
    will_remove+="• pymc_console repo ($SCRIPT_DIR)"
    
    if ! ask_yes_no "Confirm Uninstall" "\nThis will remove:\n${will_remove}\n\nContinue?"; then
        return 0
    fi
    
    print_banner
    
    # Calculate steps: repeater(optional) + console + clone(optional) + self
    local step=1
    local total=1  # self is always counted
    [[ "$has_repeater" == true ]] && ((total++))
    [[ "$has_console" == true ]] && ((total++))
    [[ "$has_clone" == true ]] && ((total++))
    
    # Step: Run upstream uninstall (if Repeater installed)
    if [[ "$has_repeater" == true ]]; then
        print_step $step $total "Removing pyMC_Repeater"
        if [[ -f "$CLONE_DIR/manage.sh" ]]; then
            # Run upstream in completely separate bash process
            # Use script -q to capture and isolate the entire session
            bash -c 'cd "'"$CLONE_DIR"'" && bash manage.sh uninstall' </dev/tty || true
        else
            # Manual cleanup if upstream not available
            systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            systemctl disable "$SERVICE_NAME" 2>/dev/null || true
            rm -f /etc/systemd/system/pymc-repeater.service
            systemctl daemon-reload
            rm -rf "$INSTALL_DIR" "$CONFIG_DIR" /var/log/pymc_repeater
            pip3 uninstall -y pymc_repeater pymc_core 2>/dev/null || true
            userdel repeater 2>/dev/null || true
        fi
        print_success "pyMC_Repeater removed"
        ((step++))
    fi
    
    # Step: Remove dashboard overlay (if exists)
    if [[ "$has_console" == true ]]; then
        print_step $step $total "Removing dashboard"
        rm -rf "$CONSOLE_DIR"
        print_success "Dashboard removed ($CONSOLE_DIR)"
        ((step++))
    fi
    
    # Step: Remove clone
    if [[ "$has_clone" == true ]]; then
        print_step $step $total "Removing pyMC_Repeater clone"
        rm -rf "$CLONE_DIR"
        print_success "Clone removed ($CLONE_DIR)"
        ((step++))
    fi
    
    # Step: Remove pymc_console repo itself (scheduled for after script exits)
    print_step $step $total "Removing pymc_console repo"
    echo -e "    ${YELLOW}Will remove $SCRIPT_DIR after script exits${NC}"
    trap "rm -rf '$SCRIPT_DIR'" EXIT
    print_success "Scheduled for removal"
    
    echo ""
    echo -e "${GREEN}${BOLD}Uninstall Complete${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Service Control (simple wrappers)
# ─────────────────────────────────────────────────────────────────────────────

do_start() {
    [[ "$EUID" -ne 0 ]] && { echo "Run as root: sudo $0 start"; return 1; }
    systemctl start "$SERVICE_NAME"
    sleep 1
    service_running && echo "✓ Service started" || echo "✗ Service failed to start"
}

do_stop() {
    [[ "$EUID" -ne 0 ]] && { echo "Run as root: sudo $0 stop"; return 1; }
    systemctl stop "$SERVICE_NAME"
    echo "✓ Service stopped"
}

do_restart() {
    [[ "$EUID" -ne 0 ]] && { echo "Run as root: sudo $0 restart"; return 1; }
    systemctl restart "$SERVICE_NAME"
    sleep 1
    service_running && echo "✓ Service restarted" || echo "✗ Service failed to start"
}

do_status() {
    if is_installed; then
        echo "pyMC_Repeater: $(get_version)"
        echo "Console:       v$(get_console_version)"
        echo "Service:       $(service_running && echo "running" || echo "stopped")"
    else
        echo "Not installed"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Menu
# ─────────────────────────────────────────────────────────────────────────────

show_menu() {
    local status="Not installed"
    is_installed && status=$(service_running && echo "Running" || echo "Stopped")
    
    local choice=$($DIALOG --backtitle "pyMC Console" --title "Main Menu" --menu \
        "\nStatus: $status\n\nSelect action:" 16 50 6 \
        "install"   "Fresh installation" \
        "upgrade"   "Upgrade existing" \
        "uninstall" "Remove everything" \
        "status"    "Show versions" \
        "logs"      "View live logs" \
        "exit"      "Exit" 3>&1 1>&2 2>&3) || return 1
    
    case "$choice" in
        install)   do_install ;;
        upgrade)   do_upgrade ;;
        uninstall) do_uninstall ;;
        status)    clear; do_status; read -p "Press Enter..." ;;
        logs)      clear; journalctl -u "$SERVICE_NAME" -f ;;
        exit)      exit 0 ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# CLI Entry Point
# ─────────────────────────────────────────────────────────────────────────────

show_help() {
    cat << EOF
pyMC Console - Dashboard Overlay Manager

Usage: $0 [command]

Commands:
  install [full|console]  Fresh installation (default: interactive)
                          full    - pyMC_Repeater + Console dashboard
                          console - Dashboard only (existing Repeater)
  upgrade                 Upgrade existing installation
  uninstall               Remove everything
  start                   Start service
  stop                    Stop service  
  restart                 Restart service
  status                  Show versions and status

Run without arguments for interactive menu.

Radio/GPIO configuration: cd $CLONE_DIR && sudo ./manage.sh
EOF
}

case "${1:-}" in
    -h|--help)  show_help ;;
    install)    setup_dialog; do_install "${2:-}" ;;
    upgrade)    setup_dialog; do_upgrade ;;
    uninstall)  setup_dialog; do_uninstall ;;
    start)      do_start ;;
    stop)       do_stop ;;
    restart)    do_restart ;;
    status)     do_status ;;
    "")
        setup_dialog
        while true; do show_menu || break; done
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
