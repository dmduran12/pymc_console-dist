#!/bin/bash
# pyMC Console Management Script
# Install, Upgrade, Configure, and Manage pymc_console stack
#
# INSTALLATION FLOW (mirrors upstream pyMC_Repeater):
# 1. User clones pymc_console to their preferred location (e.g., ~/pymc_console)
# 2. User runs: sudo ./manage.sh install
# 3. This script clones pyMC_Repeater as a sibling directory (e.g., ~/pyMC_Repeater)
# 4. Applies patches to the clone, then copies files to /opt/pymc_repeater
# 5. Installs Python packages from the clone directory
# 6. Overlays our React dashboard to the installation
#
# This matches upstream's flow where manage.sh runs from within a cloned repo
# and copies files to /opt. This makes it easier to:
# - Submit patches as PRs to upstream
# - Stay compatible with upstream updates
# - Allow users to switch between console and vanilla pyMC_Repeater

# ============================================================================
# Bootstrap Self-Healing (runs BEFORE anything else)
# ============================================================================
# Fixes chicken-and-egg: if git history diverged (e.g., after force-push),
# the old manage.sh can't pull the new manage.sh. This check runs early
# and resyncs if needed, then re-execs to run the updated script.

_bootstrap_self_heal() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Only heal if we're in a git repo and running as root (upgrade/install context)
    [ ! -d "$script_dir/.git" ] && return 0
    [ "$EUID" -ne 0 ] && return 0
    
    # Skip if BOOTSTRAP_DONE is set (prevents infinite loop)
    [ -n "$BOOTSTRAP_DONE" ] && return 0
    
    cd "$script_dir" || return 0
    git config --global --add safe.directory "$script_dir" 2>/dev/null || true
    git fetch origin 2>/dev/null || return 0
    
    local local_hash=$(git rev-parse HEAD 2>/dev/null)
    local remote_hash=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)
    
    # If already up-to-date, nothing to do
    [ -z "$remote_hash" ] && return 0
    [ "$local_hash" = "$remote_hash" ] && return 0
    
    # Check if fast-forward is possible
    if git merge-base --is-ancestor HEAD "$remote_hash" 2>/dev/null; then
        # Fast-forward works, let normal upgrade flow handle it
        return 0
    fi
    
    # History diverged! Fix it now.
    echo -e "\033[1;33m⚠ Detected diverged git history - auto-healing...\033[0m"
    if git reset --hard "origin/main" 2>/dev/null || git reset --hard "origin/master" 2>/dev/null; then
        echo -e "\033[0;32m✓ Repository synced - restarting with updated script...\033[0m"
        echo ""
        export BOOTSTRAP_DONE=1
        exec "$script_dir/manage.sh" "$@"
    else
        echo -e "\033[0;31m✗ Auto-heal failed. Manual fix: cd $script_dir && git fetch && git reset --hard origin/main\033[0m"
    fi
}

# Run bootstrap check, passing through all args for re-exec
_bootstrap_self_heal "$@"

set -e

# ============================================================================
# Path Configuration
# ============================================================================

# Script location (where pymc_console was cloned)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# pyMC_Repeater clone location (sibling to pymc_console)
# e.g., if SCRIPT_DIR is ~/dev/pymc_console, CLONE_DIR is ~/dev/pyMC_Repeater
CLONE_DIR="$(dirname "$SCRIPT_DIR")/pyMC_Repeater"

# Installation paths (where files are deployed - matches upstream)
# INSTALL_DIR: Where pyMC_Repeater is installed (matches upstream standard)
# CONSOLE_DIR: Where pymc_console stores its files (radio presets, dashboard, etc.)
# UI_DIR: Where our React dashboard is installed (separate from upstream Vue.js)
INSTALL_DIR="/opt/pymc_repeater"
CONSOLE_DIR="/opt/pymc_console"
UI_DIR="/opt/pymc_console/web/html"
CONFIG_DIR="/etc/pymc_repeater"
LOG_DIR="/var/log/pymc_repeater"
SERVICE_USER="repeater"

# Legacy alias for compatibility
REPEATER_DIR="$INSTALL_DIR"

# Service name (backend serves both API and static frontend)
BACKEND_SERVICE="pymc-repeater"

# Default branch for installations
DEFAULT_BRANCH="dev"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[97m'  # Bright white for glow effect
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Status indicators
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${CYAN}➜${NC}"
SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

# ============================================================================
# Progress Display Functions
# ============================================================================

# Print a step header
print_step() {
    local step_num="$1"
    local total_steps="$2"
    local description="$3"
    echo ""
    echo -e "${BOLD}${CYAN}[$step_num/$total_steps]${NC} ${BOLD}$description${NC}"
}

# Print success message
print_success() {
    echo -e "        ${CHECK} $1"
}

# Print error message
print_error() {
    echo -e "        ${CROSS} ${RED}$1${NC}"
}

# Print info message
print_info() {
    echo -e "        ${ARROW} $1"
}

# Print warning message
print_warning() {
    echo -e "        ${YELLOW}⚠${NC} $1"
}

# Run a command with spinner and capture output
run_with_spinner() {
    local description="$1"
    shift
    local cmd="$@"
    local log_file=$(mktemp)
    local pid
    local i=0
    
    # Start command in background
    eval "$cmd" > "$log_file" 2>&1 &
    pid=$!
    
    # Show spinner while command runs
    printf "        ${DIM}%s${NC} " "$description"
    while kill -0 $pid 2>/dev/null; do
        printf "\r        ${CYAN}%s${NC} %s" "${SPINNER_CHARS:i++%${#SPINNER_CHARS}:1}" "$description"
        sleep 0.1
    done
    
    # Get exit status
    wait $pid
    local exit_code=$?
    
    # Clear spinner line and show result
    printf "\r        "  # Clear the line
    if [ $exit_code -eq 0 ]; then
        echo -e "${CHECK} $description"
        rm -f "$log_file"
        return 0
    else
        echo -e "${CROSS} ${RED}$description${NC}"
        echo -e "        ${DIM}Log output:${NC}"
        tail -20 "$log_file" | sed 's/^/        /' 
        rm -f "$log_file"
        return 1
    fi
}

# Run a command and show immediate output (for long operations)
run_with_output() {
    local description="$1"
    shift
    local cmd="$@"
    
    echo -e "        ${ARROW} $description"
    echo -e "        ${DIM}─────────────────────────────────────────${NC}"
    
    # Run command with indented output
    if eval "$cmd" 2>&1 | sed 's/^/        /'; then
        echo -e "        ${DIM}─────────────────────────────────────────${NC}"
        print_success "$description completed"
        return 0
    else
        echo -e "        ${DIM}─────────────────────────────────────────${NC}"
        print_error "$description failed"
        return 1
    fi
}

# Show a progress bar (updates in place)
# Usage: show_progress_bar current total [description]
show_progress_bar() {
    local current=$1
    local total=$2
    local description="${3:-}"
    local width=30
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    # Build the bar
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    # Print with carriage return to update in place
    printf "\r        ${CYAN}[${bar}]${NC} ${percent}%% ${DIM}${description}${NC}  "
}

# Run a long command with elapsed time display
run_with_elapsed_time() {
    local description="$1"
    shift
    local cmd="$@"
    local log_file=$(mktemp)
    local pid
    local start_time=$(date +%s)
    
    # Start command in background
    eval "$cmd" > "$log_file" 2>&1 &
    pid=$!
    
    # Show elapsed time while command runs
    printf "        ${ARROW} %s " "$description"
    while kill -0 $pid 2>/dev/null; do
        local elapsed=$(($(date +%s) - start_time))
        local mins=$((elapsed / 60))
        local secs=$((elapsed % 60))
        printf "\r        ${CYAN}⏱${NC}  %s ${DIM}(%dm %02ds)${NC}  " "$description" $mins $secs
        sleep 1
    done
    
    # Get exit status
    wait $pid
    local exit_code=$?
    local elapsed=$(($(date +%s) - start_time))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    
    # Clear line and show result
    printf "\r        "  # Clear
    if [ $exit_code -eq 0 ]; then
        echo -e "${CHECK} $description ${DIM}(${mins}m ${secs}s)${NC}"
        rm -f "$log_file"
        return 0
    else
        echo -e "${CROSS} ${RED}$description${NC} ${DIM}(${mins}m ${secs}s)${NC}"
        echo -e "        ${DIM}Log output:${NC}"
        tail -20 "$log_file" | sed 's/^/        /' 
        rm -f "$log_file"
        return 1
    fi
}

# Run pip install with real progress bar
# Parses pip output to show download/install progress
run_pip_with_progress() {
    local description="$1"
    shift
    local cmd="$@"
    local log_file=$(mktemp)
    local progress_file=$(mktemp)
    local pid
    local start_time=$(date +%s)
    local width=30
    
    # Start command in background, capturing output for parsing
    eval "$cmd" 2>&1 | tee "$log_file" | while IFS= read -r line; do
        # Look for pip progress indicators
        if [[ "$line" =~ Downloading\ .*\ \(([0-9.]+)\ ([kMG]?B)\) ]]; then
            echo "Downloading..." > "$progress_file"
        elif [[ "$line" =~ Installing\ collected\ packages ]]; then
            echo "Installing..." > "$progress_file"
        elif [[ "$line" =~ Successfully\ installed ]]; then
            echo "Done" > "$progress_file"
        fi
    done &
    pid=$!
    
    # Show progress while command runs
    local phase="Starting"
    printf "        ${ARROW} %s " "$description"
    while kill -0 $pid 2>/dev/null; do
        local elapsed=$(($(date +%s) - start_time))
        local mins=$((elapsed / 60))
        local secs=$((elapsed % 60))
        
        # Read current phase if available
        [ -f "$progress_file" ] && phase=$(cat "$progress_file" 2>/dev/null || echo "$phase")
        
        # Build animated bar
        local anim_pos=$(( (elapsed * 2) % width ))
        local bar=""
        for ((i=0; i<width; i++)); do
            if [ $i -eq $anim_pos ] || [ $i -eq $((anim_pos + 1)) ]; then
                bar+="█"
            else
                bar+="░"
            fi
        done
        
        printf "\r        ${CYAN}[${bar}]${NC} %s ${DIM}(%dm %02ds)${NC}  " "$phase" $mins $secs
        sleep 0.5
    done
    
    # Get exit status
    wait $pid
    local exit_code=$?
    local elapsed=$(($(date +%s) - start_time))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    
    # Cleanup
    rm -f "$progress_file"
    
    # Clear line and show result
    printf "\r%-80s\r" " "  # Clear the line
    if [ $exit_code -eq 0 ]; then
        echo -e "        ${CHECK} $description ${DIM}(${mins}m ${secs}s)${NC}"
        rm -f "$log_file"
        return 0
    else
        echo -e "        ${CROSS} ${RED}$description${NC} ${DIM}(${mins}m ${secs}s)${NC}"
        echo -e "        ${DIM}Log output:${NC}"
        tail -20 "$log_file" | sed 's/^/        /' 
        rm -f "$log_file"
        return 1
    fi
}

# Attempt cubic-in-out easing using bash integer math (approximation)
# Returns position 0-100 given input 0-100
cubic_ease_inout() {
    local t=$1  # 0-100
    if [ $t -lt 50 ]; then
        # Ease in: 4 * t^3 (scaled)
        echo $(( (4 * t * t * t) / 10000 ))
    else
        # Ease out: 1 - (-2t + 2)^3 / 2
        local p=$((100 - t))
        echo $(( 100 - (4 * p * p * p) / 10000 ))
    fi
}

# Calculate velocity (derivative) of cubic ease-in-out at point t
# Returns 0-100 where 100 is max velocity (at t=50, the inflection point)
cubic_ease_velocity() {
    local t=$1  # 0-100
    # Derivative of cubic ease-in-out: 6t(1-t) scaled to 0-100
    # Max velocity occurs at t=50 (middle of the curve)
    # At t=0 or t=100, velocity is 0 (stationary at endpoints)
    local velocity=$(( (6 * t * (100 - t)) / 100 ))
    # Normalize to 0-100 range (max is 150 at t=50, so scale by 2/3)
    echo $(( (velocity * 100) / 150 ))
}

# Run npm with animated progress bar
run_npm_with_progress() {
    local description="$1"
    shift
    local cmd="$@"
    local log_file=$(mktemp)
    local pid
    local start_time=$(date +%s)
    local width=40
    local cycle_frames=40  # frames per half-cycle (faster, smoother animation)
    local cursor_width=2   # narrower cursor for higher fidelity
    
    # Start command in background
    eval "$cmd" > "$log_file" 2>&1 &
    pid=$!
    
    # Show animated progress bar while command runs
    printf "        ${ARROW} %s " "$description"
    local frame=0
    while kill -0 $pid 2>/dev/null; do
        local elapsed=$(($(date +%s) - start_time))
        local mins=$((elapsed / 60))
        local secs=$((elapsed % 60))
        
        # Calculate position in cycle (0 to cycle_frames*2)
        local cycle_pos=$(( frame % (cycle_frames * 2) ))
        local going_right=1
        [ $cycle_pos -ge $cycle_frames ] && going_right=0
        
        # Get linear position within half-cycle (0-100)
        local linear_t
        if [ $going_right -eq 1 ]; then
            linear_t=$(( (cycle_pos * 100) / cycle_frames ))
        else
            linear_t=$(( ((cycle_frames * 2 - cycle_pos) * 100) / cycle_frames ))
        fi
        
        # Apply cubic easing
        local eased_t=$(cubic_ease_inout $linear_t)
        
        # Calculate velocity for motion blur and glow effects
        local velocity=$(cubic_ease_velocity $linear_t)
        
        # Convert to bar position
        local anim_pos=$(( (eased_t * (width - cursor_width)) / 100 ))
        
        # Determine trail intensity based on velocity (motion blur when fast)
        # velocity 0-60: no trail, 60-85: near trail, 85+: full trail
        local show_near_trail=0
        [ $velocity -gt 60 ] && show_near_trail=1
        local show_far_trail=0
        [ $velocity -gt 85 ] && show_far_trail=1
        
        # Glow on cursor at apex velocity (tight window: 90-100%)
        local cursor_glow=0
        [ $velocity -gt 90 ] && cursor_glow=1
        
        # Build bar with velocity-based effects
        local bar=""
        for ((j=0; j<width; j++)); do
            local dist_from_cursor
            if [ $j -lt $anim_pos ]; then
                dist_from_cursor=$((anim_pos - j))
            elif [ $j -ge $((anim_pos + cursor_width)) ]; then
                dist_from_cursor=$((j - anim_pos - cursor_width + 1))
            else
                dist_from_cursor=0
            fi
            
            # Build character with motion blur effect
            if [ $dist_from_cursor -eq 0 ]; then
                # Solid cursor - glow at apex velocity (just turns white)
                if [ $cursor_glow -eq 1 ]; then
                    bar+="${WHITE}█${CYAN}"  # White cursor at peak velocity
                else
                    bar+="█"  # Normal cyan cursor
                fi
            elif [ $dist_from_cursor -eq 1 ] && [ $show_near_trail -eq 1 ]; then
                bar+="▓"  # Near motion blur - appears when moving
            elif [ $dist_from_cursor -eq 2 ] && [ $show_far_trail -eq 1 ]; then
                bar+="▒"  # Far motion blur - only at high speed  
            else
                bar+="░"  # Empty background
            fi
        done
        
        printf "\r        ${CYAN}[${bar}]${NC} %s ${DIM}(%dm %02ds)${NC}  " "$description" $mins $secs
        sleep 0.033  # ~30fps for smoother animation
        ((frame++)) || true
    done
    
    # Get exit status
    wait $pid
    local exit_code=$?
    local elapsed=$(($(date +%s) - start_time))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    
    # Clear line and show result
    printf "\r%-80s\r" " "  # Clear the line
    if [ $exit_code -eq 0 ]; then
        echo -e "        ${CHECK} $description ${DIM}(${mins}m ${secs}s)${NC}"
        rm -f "$log_file"
        return 0
    else
        echo -e "        ${CROSS} ${RED}$description${NC} ${DIM}(${mins}m ${secs}s)${NC}"
        echo -e "        ${DIM}Log output:${NC}"
        tail -30 "$log_file" | sed 's/^/        /' 
        rm -f "$log_file"
        return 1
    fi
}

# Run git clone with real-time progress display
# Shows actual git progress (objects, files) as they're received
run_git_clone_with_progress() {
    local branch="$1"
    local repo_url="$2"
    local target_dir="$3"
    local start_time=$(date +%s)
    
    echo -e "        ${ARROW} Cloning from ${CYAN}github.com/rightup/pyMC_Repeater${NC}"
    echo -e "        ${DIM}────────────────────────────────────────${NC}"
    
    # Run git clone with progress, parse and display key lines
    git clone -b "$branch" --progress "$repo_url" "$target_dir" 2>&1 | while IFS= read -r line; do
        # Parse git progress output
        if [[ "$line" =~ ^Cloning ]]; then
            printf "\r        ${DIM}%-50s${NC}" "Initializing..."
        elif [[ "$line" =~ ^remote:\ Enumerating ]]; then
            printf "\r        ${DIM}%-50s${NC}" "Enumerating objects..."
        elif [[ "$line" =~ ^remote:\ Counting ]]; then
            printf "\r        ${DIM}%-50s${NC}" "Counting objects..."
        elif [[ "$line" =~ ^remote:\ Compressing ]]; then
            # Extract percentage if present
            if [[ "$line" =~ ([0-9]+)% ]]; then
                printf "\r        ${CYAN}Compressing:${NC} ${BASH_REMATCH[1]}%%%-30s" " "
            fi
        elif [[ "$line" =~ ^Receiving\ objects ]]; then
            # Extract percentage
            if [[ "$line" =~ ([0-9]+)% ]]; then
                printf "\r        ${CYAN}Receiving:${NC}   ${BASH_REMATCH[1]}%%%-30s" " "
            fi
        elif [[ "$line" =~ ^Resolving\ deltas ]]; then
            # Extract percentage
            if [[ "$line" =~ ([0-9]+)% ]]; then
                printf "\r        ${CYAN}Resolving:${NC}   ${BASH_REMATCH[1]}%%%-30s" " "
            fi
        elif [[ "$line" =~ ^Updating\ files ]]; then
            # Extract percentage
            if [[ "$line" =~ ([0-9]+)% ]]; then
                printf "\r        ${CYAN}Extracting:${NC}  ${BASH_REMATCH[1]}%%%-30s" " "
            fi
        fi
    done
    
    local exit_code=${PIPESTATUS[0]}
    local elapsed=$(($(date +%s) - start_time))
    
    # Clear progress line
    printf "\r%-60s\r" " "
    echo -e "        ${DIM}────────────────────────────────────────${NC}"
    
    if [ $exit_code -eq 0 ]; then
        print_success "Repository cloned ${DIM}(${elapsed}s)${NC}"
        return 0
    else
        print_error "Clone failed"
        return 1
    fi
}

# Print installation banner
print_banner() {
    clear
    echo ""
    echo -e "${BOLD}${CYAN}pyMC Console Installer${NC}"
    echo -e "${DIM}React Dashboard + LoRa Mesh Network Repeater${NC}"
    echo ""
}

# Print completion summary
print_completion() {
    local ip_address="$1"
    echo ""
    echo -e "${GREEN}${BOLD}Installation Complete!${NC} ${CHECK}"
    echo ""
    
    # Version and branch summary
    echo -e "${BOLD}Installed Versions:${NC}"
    local core_ver=$(get_core_version)
    local repeater_ver=$(get_repeater_version)
    local console_ver=$(get_console_version)
    local repeater_branch=$(get_repeater_branch)
    local core_branch=$(get_core_branch_from_toml "$CLONE_DIR")
    echo -e "  ${DIM}pyMC Core:${NC}     ${CYAN}v${core_ver}${NC}  ${DIM}@${core_branch}${NC}"
    echo -e "  ${DIM}pyMC Repeater:${NC} ${CYAN}v${repeater_ver}${NC}  ${DIM}@${repeater_branch}${NC}"
    echo -e "  ${DIM}pyMC Console:${NC}  ${CYAN}${console_ver}${NC}"
    echo ""
    
    # Disk usage report
    echo -e "${BOLD}Disk Usage:${NC}"
    local install_size=$(du -sh "$REPEATER_DIR" 2>/dev/null | cut -f1 || echo "N/A")
    local config_size=$(du -sh "$CONFIG_DIR" 2>/dev/null | cut -f1 || echo "N/A")
    echo -e "  ${DIM}Installation:${NC}  $install_size"
    echo -e "  ${DIM}Configuration:${NC} $config_size"
    echo ""
    
    echo -e "${BOLD}Access your dashboard:${NC}"
    echo -e "  ${ARROW} Dashboard: ${CYAN}http://$ip_address:8000/${NC}"
    echo -e "  ${DIM}(API endpoints also available at /api/*)${NC}"
    echo ""
}

# Cleanup function for error handling
cleanup_on_error() {
    echo ""
    print_error "Installation failed!"
    echo ""
    echo -e "  ${YELLOW}Partial installation may remain. To clean up:${NC}"
    echo -e "  ${DIM}sudo ./manage.sh uninstall${NC}"
    echo ""
    echo -e "  ${YELLOW}Check the error messages above for details.${NC}"
    echo -e "  ${YELLOW}Common issues:${NC}"
    echo -e "  ${DIM}- Network connectivity problems${NC}"
    echo -e "  ${DIM}- Missing system dependencies${NC}"
    echo -e "  ${DIM}- Insufficient disk space${NC}"
    echo -e "  ${DIM}- Permission issues${NC}"
    echo ""
}

# ============================================================================
# TUI Setup
# ============================================================================

# Check if running in interactive terminal
check_terminal() {
    if [ ! -t 0 ] || [ -z "$TERM" ]; then
        echo "Error: This script requires an interactive terminal."
        echo "Please run from SSH or a local terminal."
        exit 1
    fi
}

# Setup dialog/whiptail
setup_dialog() {
    if command -v whiptail &> /dev/null; then
        DIALOG="whiptail"
    elif command -v dialog &> /dev/null; then
        DIALOG="dialog"
    else
        echo "TUI interface requires whiptail or dialog."
        if [ "$EUID" -eq 0 ]; then
            echo "Installing whiptail..."
            apt-get update -qq && apt-get install -y whiptail
            DIALOG="whiptail"
        else
            echo ""
            echo "Please install whiptail: sudo apt-get install -y whiptail"
            exit 1
        fi
    fi
}

# ============================================================================
# Dialog Helper Functions
# ============================================================================

show_info() {
    $DIALOG --backtitle "pyMC Console Management" --title "$1" --msgbox "$2" 14 70
}

show_error() {
    $DIALOG --backtitle "pyMC Console Management" --title "Error" --msgbox "$1" 10 60
}

ask_yes_no() {
    $DIALOG --backtitle "pyMC Console Management" --title "$1" --yesno "$2" 12 70
}

get_input() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    $DIALOG --backtitle "pyMC Console Management" --title "$title" --inputbox "$prompt" 10 70 "$default" 3>&1 1>&2 2>&3
}

# ============================================================================
# Status Check Functions
# ============================================================================

is_installed() {
    [ -d "$REPEATER_DIR" ] && [ -f "$REPEATER_DIR/pyproject.toml" ]
}

backend_running() {
    systemctl is-active "$BACKEND_SERVICE" >/dev/null 2>&1
}

# Get pymc_core branch/ref from a pyproject.toml file
# Usage: get_core_branch_from_toml [path_to_dir_with_toml]
# Returns: branch name (e.g., "feat/anon-req", "main") or "unknown"
get_core_branch_from_toml() {
    local dir="${1:-$CLONE_DIR}"
    local toml_file="$dir/pyproject.toml"
    
    if [ ! -f "$toml_file" ]; then
        echo "unknown"
        return
    fi
    
    # Extract pymc_core git reference from pyproject.toml
    # Format: "pymc_core[hardware] @ git+https://github.com/rightup/pyMC_core.git@feat/anon-req"
    local branch
    branch=$(grep -i 'pymc_core.*@.*git+' "$toml_file" 2>/dev/null | sed -n 's/.*\.git@\([^"]*\).*/\1/p' | head -1)
    
    if [ -n "$branch" ]; then
        echo "$branch"
    else
        echo "unknown"
    fi
}

# Get pyMC_Repeater branch from clone directory
get_repeater_branch() {
    if [ -d "$CLONE_DIR/.git" ]; then
        cd "$CLONE_DIR" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Get pyMC Repeater version from installed pyproject.toml
get_version() {
    if [ -f "$REPEATER_DIR/pyproject.toml" ]; then
        grep "^version" "$REPEATER_DIR/pyproject.toml" | cut -d'"' -f2 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

# Get pyMC Repeater version (alias for clarity)
get_repeater_version() {
    get_version
}

# Get pymc_core version from installed pip package
get_core_version() {
    # Try to get version from pip
    local version
    version=$(pip3 show pymc_core 2>/dev/null | grep "^Version:" | awk '{print $2}')
    if [ -n "$version" ]; then
        echo "$version"
    else
        echo "unknown"
    fi
}

# Get pyMC Console (UI) version from installed VERSION file or GitHub API
get_console_version() {
    local ui_dir="$UI_DIR"
    
    if [ -d "$ui_dir" ]; then
        # First, try to read VERSION file (created during build)
        if [ -f "$ui_dir/VERSION" ]; then
            local ver=$(cat "$ui_dir/VERSION" 2>/dev/null | tr -d '[:space:]')
            if [ -n "$ver" ]; then
                echo "v$ver"
                return 0
            fi
        fi
        
        # Fallback: check GitHub API for latest release
        local latest_tag
        latest_tag=$(curl -s --max-time 3 "https://api.github.com/repos/${UI_REPO}/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
        if [ -n "$latest_tag" ]; then
            echo "$latest_tag"
        else
            echo "installed"
        fi
    else
        echo "not installed"
    fi
}

get_status_display() {
    if ! is_installed; then
        echo "Not Installed"
    else
        local version=$(get_version)
        local status="Stopped"
        
        backend_running && status="Running"
        
        echo "v$version | Service: $status"
    fi
}

# ============================================================================
# Install Function
# ============================================================================

do_install() {
    # Check if already installed
    if is_installed; then
        show_error "pyMC Console is already installed!\n\npyMC_Repeater: $INSTALL_DIR\n\nUse 'upgrade' to update or 'uninstall' first."
        return 1
    fi
    
    # Check root
    if [ "$EUID" -ne 0 ]; then
        show_error "Installation requires root privileges.\n\nPlease run: sudo $0 install"
        return 1
    fi
    
    # Branch selection
    local branch="${1:-}"
    if [ -z "$branch" ]; then
        branch=$($DIALOG --backtitle "pyMC Console Management" --title "Select Branch" --menu "\nSelect the pyMC_Repeater branch to install:" 15 65 4 \
            "dev" "Development branch (recommended)" \
            "main" "Stable release" \
            "feat/dmg" "DMG branch (experimental)" \
            "custom" "Enter custom branch name" 3>&1 1>&2 2>&3)
        
        if [ -z "$branch" ]; then
            return 0  # User cancelled
        fi
        
        if [ "$branch" = "custom" ]; then
            branch=$(get_input "Custom Branch" "Enter the branch name:" "dev")
            if [ -z "$branch" ]; then
                return 0
            fi
        fi
    fi
    
    # Welcome screen
    $DIALOG --backtitle "pyMC Console Management" --title "Welcome" --msgbox "\nWelcome to pyMC Console Setup\n\nThis will install:\n- pyMC Repeater (LoRa mesh repeater)\n- pyMC Console (React dashboard)\n\nBranch: $branch\nClone: $CLONE_DIR\nInstall: $INSTALL_DIR\n\nPress OK to continue..." 18 70
    
    # SPI Check (Raspberry Pi)
    check_spi
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Print banner
    print_banner
    echo -e "  ${DIM}Branch: $branch${NC}"
    echo -e "  ${DIM}Clone: $CLONE_DIR${NC}"
    echo -e "  ${DIM}Install: $INSTALL_DIR${NC}"
    
    local total_steps=6
    
    # =========================================================================
    # Step 1: Install prerequisites (whiptail needed by upstream)
    # =========================================================================
    print_step 1 $total_steps "Installing prerequisites"
    
    run_with_spinner "Updating package lists" "apt-get update -qq" || {
        print_error "Failed to update package lists"
        return 1
    }
    
    # Install whiptail (needed by upstream) and git
    run_with_spinner "Installing required packages" "apt-get install -y whiptail git curl" || {
        print_error "Failed to install prerequisites"
        return 1
    }
    
    # Install yq (we use it for config manipulation)
    if ! command -v yq &> /dev/null || [[ "$(yq --version 2>&1)" != *"mikefarah/yq"* ]]; then
        run_with_spinner "Installing yq" "install_yq_silent" || print_warning "yq installation failed (non-critical)"
    else
        print_success "yq already installed"
    fi
    
    # =========================================================================
    # Step 2: Clone pyMC_Repeater
    # =========================================================================
    print_step 2 $total_steps "Cloning pyMC_Repeater@$branch"
    
    # Remove existing clone if present (fresh install)
    if [ -d "$CLONE_DIR" ]; then
        print_info "Removing existing clone at $CLONE_DIR"
        rm -rf "$CLONE_DIR"
    fi
    
    # Mark directories as safe for git (running as root on user-owned dir)
    git config --global --add safe.directory "$CLONE_DIR" 2>/dev/null || true
    git config --global --add safe.directory "$INSTALL_DIR" 2>/dev/null || true
    
    run_git_clone_with_progress "$branch" "https://github.com/rightup/pyMC_Repeater.git" "$CLONE_DIR" || {
        print_error "Failed to clone pyMC_Repeater"
        print_info "Check if branch '$branch' exists"
        return 1
    }
    
    # Show verified git info so user can confirm what was cloned
    cd "$CLONE_DIR"
    local git_branch=$(git rev-parse --abbrev-ref HEAD)
    local git_commit=$(git rev-parse --short HEAD)
    local git_date=$(git log -1 --format=%cd --date=short)
    local git_msg=$(git log -1 --format=%s | cut -c1-50)
    echo -e "        ${BOLD}Source Verification${NC}"
    echo -e "        Branch:  ${CYAN}${git_branch}${NC}"
    echo -e "        Commit:  ${CYAN}${git_commit}${NC} ${DIM}(${git_date})${NC}"
    echo -e "        Message: ${DIM}${git_msg}...${NC}"
    echo ""
    
    # =========================================================================
    # Step 3: Run upstream installer (via UPSTREAM INSTALLATION MANAGER)
    # =========================================================================
    print_step 3 $total_steps "Running pyMC_Repeater installer"
    
    # This runs upstream's manage.sh install with our fake dialog to bypass TUI
    # Upstream handles: user creation, directories, deps, pip install, service, config
    run_upstream_installer "install" "$branch" || {
        print_error "Upstream installation failed"
        return 1
    }
    
    # =========================================================================
    # Step 4: Apply log level API patch
    # =========================================================================
    print_step 4 $total_steps "Configuring log level API"
    
    # Apply single patch: POST /api/set_log_level endpoint for Logs page toggle
    # Will be removed once upstream merges this feature
    patch_log_level_api "$INSTALL_DIR"
    
    # =========================================================================
    # Step 5: Install dashboard and console extras
    # =========================================================================
    print_step 5 $total_steps "Installing pyMC Console dashboard"
    
    # Create console directory for our extras
    mkdir -p "$CONSOLE_DIR"
    
    # Copy radio settings files to console dir
    if [ -f "$CLONE_DIR/radio-settings.json" ]; then
        cp "$CLONE_DIR/radio-settings.json" "$CONSOLE_DIR/"
        print_success "Copied radio-settings.json"
    fi
    
    if [ -f "$CLONE_DIR/radio-presets.json" ]; then
        cp "$CLONE_DIR/radio-presets.json" "$CONSOLE_DIR/"
        print_success "Copied radio-presets.json"
    fi
    
    # Install our React dashboard (overlays upstream's Vue.js frontend)
    install_static_frontend || {
        print_error "Frontend installation failed"
        return 1
    }
    
    # Fix permissions for console directory
    chown -R "$SERVICE_USER:$SERVICE_USER" "$CONSOLE_DIR" 2>/dev/null || true
    
    # =========================================================================
    # Step 6: Finalize installation
    # =========================================================================
    print_step 6 $total_steps "Finalizing installation"
    
    # Stop service for now - we'll start it after user configures radio
    # Upstream may have started it, so stop to avoid running with default config
    systemctl stop "$BACKEND_SERVICE" 2>/dev/null || true
    print_success "Installation files ready"
    print_info "Service will start after radio configuration"
    
    # Clear error trap
    trap - ERR
    
    # =========================================================================
    # Radio Configuration (terminal-based)
    # =========================================================================
    echo ""
    echo -e "${BOLD}${CYAN}Radio Configuration${NC}"
    echo -e "${DIM}Configure your radio settings for your region and hardware${NC}"
    echo ""
    
    configure_radio_terminal
    
    # NOW start the service with user's configuration
    print_info "Starting service with your configuration..."
    systemctl daemon-reload
    systemctl start "$BACKEND_SERVICE" 2>/dev/null || true
    sleep 2
    if backend_running; then
        print_success "Backend service running"
    else
        print_warning "Service may need GPIO configuration - use './manage.sh gpio'"
    fi
    
    # Show completion
    local ip_address=$(hostname -I | awk '{print $1}')
    print_completion "$ip_address"
    
    echo -e "${BOLD}Manage your installation:${NC}"
    echo -e "  ${DIM}./manage.sh settings${NC}  - Configure radio"
    echo -e "  ${DIM}./manage.sh gpio${NC}      - Configure GPIO pins"
    echo -e "  ${DIM}./manage.sh${NC}           - Full management menu"
    echo ""
}

# ============================================================================
# Upgrade Function
# ============================================================================

do_upgrade() {
    if ! is_installed; then
        show_error "pyMC Console is not installed!\n\nUse 'install' first."
        return 1
    fi
    
    if [ "$EUID" -ne 0 ]; then
        show_error "Upgrade requires root privileges.\n\nPlease run: sudo $0 upgrade"
        return 1
    fi
    
    # Self-update: pull latest pymc_console repo first, then re-exec if updated
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -d "$script_dir/.git" ]; then
        echo ""
        print_info "Checking for pymc_console updates..."
        git config --global --add safe.directory "$script_dir" 2>/dev/null || true
        cd "$script_dir"
        
        # Check if there are updates available
        git fetch origin 2>/dev/null || true
        local local_hash=$(git rev-parse HEAD 2>/dev/null)
        local remote_hash=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)
        
        if [ -n "$remote_hash" ] && [ "$local_hash" != "$remote_hash" ]; then
            print_info "Updates available, pulling..."
            # Try fast-forward first, fall back to reset if history diverged (e.g., after force-push)
            if git pull --ff-only 2>/dev/null; then
                print_success "pymc_console updated - restarting with new version..."
                echo ""
                exec "$script_dir/manage.sh" upgrade
            elif git reset --hard "origin/main" 2>/dev/null || git reset --hard "origin/master" 2>/dev/null; then
                print_success "pymc_console synced (history was rewritten) - restarting..."
                echo ""
                exec "$script_dir/manage.sh" upgrade
            else
                print_warning "Could not auto-update pymc_console (continuing with current version)"
                print_info "You may need to manually run: cd $script_dir && git fetch && git reset --hard origin/main"
            fi
        else
            print_success "pymc_console is up to date"
        fi
        echo ""
    fi
    
    # Capture current versions BEFORE upgrade
    local current_repeater_ver=$(get_repeater_version)
    local current_core_ver=$(get_core_version)
    local current_console_ver=$(get_console_version)
    
    # Get current branch from clone directory or default to feat/dmg
    local current_branch="$DEFAULT_BRANCH"
    if [ -d "$CLONE_DIR/.git" ]; then
        cd "$CLONE_DIR" 2>/dev/null || true
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$DEFAULT_BRANCH")
    fi
    
    # Show current versions and upgrade type selection
    local upgrade_type
    upgrade_type=$($DIALOG --backtitle "pyMC Console Management" --title "Upgrade Options" --menu "
 Current Installed Versions:
 ─────────────────────────────────────
   pyMC Core:      v${current_core_ver}
   pyMC Repeater:  v${current_repeater_ver}
   pyMC Console:   ${current_console_ver}
 ─────────────────────────────────────

 Select upgrade type:" 19 65 2 \
        "<Console>" "Console Only" \
        "<Package>" "Full pyMC Stack" 3>&1 1>&2 2>&3)
    
    if [ -z "$upgrade_type" ]; then
        return 0
    fi
    
    local branch="$current_branch"
    local skip_backend=false
    
    if [ "$upgrade_type" = "<Console>" ]; then
        # Console-only upgrade
        skip_backend=true
        
        if ! ask_yes_no "Confirm Console Upgrade" "
This will ONLY update the pyMC Console dashboard.

pyMC Core and pyMC Repeater will NOT be modified.

Current Console: ${current_console_ver}
New Console:     Latest from GitHub

Continue?"; then
            return 0
        fi
    else
        # Full upgrade - select branch
        branch=$($DIALOG --backtitle "pyMC Console Management" --title "Select Branch" --menu "
 Full upgrade will update:
   • pyMC Core (mesh library)
   • pyMC Repeater (backend)
   • pyMC Console (dashboard)

 Current branch: $current_branch

 Select the branch for pyMC Repeater:" 19 65 5 \
            "dev" "Development branch (recommended)" \
            "main" "Stable release" \
            "feat/dmg" "DMG branch (experimental)" \
            "keep" "Keep current branch ($current_branch)" \
            "custom" "Enter custom branch name" 3>&1 1>&2 2>&3)
        
        if [ -z "$branch" ]; then
            return 0  # User cancelled
        fi
        
        if [ "$branch" = "keep" ]; then
            branch="$current_branch"
        elif [ "$branch" = "custom" ]; then
            branch=$(get_input "Custom Branch" "Enter the branch name:" "$current_branch")
            if [ -z "$branch" ]; then
                return 0
            fi
        fi
        
        if ! ask_yes_no "Confirm Full Upgrade" "
This will update ALL components:

  pyMC Core:     v${current_core_ver} → (via pip)
  pyMC Repeater: v${current_repeater_ver} → $branch branch
  pyMC Console:  ${current_console_ver} → Latest

Your configuration will be preserved.

Continue?"; then
            return 0
        fi
    fi
    
    # Print banner
    print_banner
    if [ "$skip_backend" = true ]; then
        echo -e "  ${DIM}Upgrade type: Console Only${NC}"
    else
        echo -e "  ${DIM}Upgrade type: Full (Core + Repeater + Console)${NC}"
        echo -e "  ${DIM}Target branch: $branch${NC}"
    fi
    echo ""
    echo -e "  ${BOLD}Current Versions:${NC}"
    echo -e "  ${DIM}pyMC Core:${NC}     v${current_core_ver}"
    echo -e "  ${DIM}pyMC Repeater:${NC} v${current_repeater_ver}"
    echo -e "  ${DIM}pyMC Console:${NC}  ${current_console_ver}"
    
    local total_steps
    if [ "$skip_backend" = true ]; then
        total_steps=3
    else
        total_steps=5
    fi
    
    local step_num=0
    
    # =========================================================================
    # Step 1: Backup configuration (both paths)
    # =========================================================================
    ((step_num++)) || true
    print_step $step_num $total_steps "Backing up configuration"
    local backup_file="$CONFIG_DIR/config.yaml.backup.$(date +%Y%m%d_%H%M%S)"
    if [ -f "$CONFIG_DIR/config.yaml" ]; then
        cp "$CONFIG_DIR/config.yaml" "$backup_file"
        print_success "Backup saved to: $backup_file"
    else
        print_info "No existing config to backup"
    fi
    
    # =========================================================================
    # CONSOLE-ONLY PATH: Skip backend, just update dashboard
    # =========================================================================
    if [ "$skip_backend" = true ]; then
        # Step 2: Update dashboard only
        ((step_num++)) || true
        print_step $step_num $total_steps "Updating pyMC Console dashboard"
        install_static_frontend || {
            print_error "Dashboard update failed"
            return 1
        }
        
        # Step 3: Restart service
        ((step_num++)) || true
        print_step $step_num $total_steps "Restarting service"
        systemctl restart "$BACKEND_SERVICE" 2>/dev/null || true
        sleep 2
        if backend_running; then
            print_success "Service running"
        else
            print_warning "Service may need configuration"
        fi
        
        # Show completion (console only)
        local new_console_ver=$(get_console_version)
        local ip_address=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
        
        echo ""
        echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}${GREEN}  Console Upgrade Complete!${NC}"
        echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo ""
    # Get branch info
    local repeater_branch=$(get_repeater_branch)
    local core_branch=$(get_core_branch_from_toml "$CLONE_DIR")
    
    echo -e "  ${BOLD}Versions:${NC}"
    echo -e "  ${DIM}pyMC Core:${NC}     v${current_core_ver} ${DIM}(unchanged)${NC}  ${DIM}@${core_branch}${NC}"
    echo -e "  ${DIM}pyMC Repeater:${NC} v${current_repeater_ver} ${DIM}(unchanged)${NC}  ${DIM}@${repeater_branch}${NC}"
    echo -e "  ${CHECK} pyMC Console:  ${DIM}${current_console_ver}${NC} → ${CYAN}${new_console_ver}${NC}"
    echo ""
    echo -e "  ${CHECK} Configuration preserved"
    echo -e "  ${CHECK} Dashboard: ${CYAN}http://$ip_address:8000${NC}"
        echo ""
        return 0
    fi
    
    # =========================================================================
    # FULL UPGRADE PATH: Update Repeater, Core, and Console
    # =========================================================================
    
    # Step 2: Update pyMC_Repeater clone
    ((step_num++)) || true
    print_step $step_num $total_steps "Updating pyMC_Repeater@$branch"
    
    # Mark directories as safe for git (running as root on user-owned dir)
    git config --global --add safe.directory "$CLONE_DIR" 2>/dev/null || true
    git config --global --add safe.directory "$INSTALL_DIR" 2>/dev/null || true
    
    # If clone doesn't exist, clone fresh
    if [ ! -d "$CLONE_DIR/.git" ]; then
        print_info "Clone not found, creating fresh clone..."
        rm -rf "$CLONE_DIR" 2>/dev/null || true
        run_git_clone_with_progress "$branch" "https://github.com/rightup/pyMC_Repeater.git" "$CLONE_DIR" || {
            print_error "Failed to clone pyMC_Repeater"
            return 1
        }
    else
        cd "$CLONE_DIR"
        
        run_with_spinner "Fetching updates" "git fetch origin --prune" || {
            print_error "Failed to fetch updates"
            return 1
        }
        
        # Reset any local changes (from previous patches)
        git reset --hard HEAD 2>/dev/null || true
        git clean -fd 2>/dev/null || true
        
        # Switch to the target branch
        # First try to checkout existing branch, if that fails create tracking branch
        if ! git checkout "$branch" 2>/dev/null; then
            # Branch doesn't exist locally, create it tracking origin
            if git checkout -b "$branch" "origin/$branch" 2>/dev/null; then
                print_success "Switched to new branch: $branch"
            else
                print_error "Branch '$branch' not found on remote"
                print_info "Available branches: $(git branch -r | grep -v HEAD | sed 's/origin\///' | tr '\n' ' ')"
                return 1
            fi
        fi
        
        # Pull latest changes (use reset to handle any divergence)
        run_with_spinner "Pulling latest changes" "git reset --hard origin/$branch" || {
            print_error "Failed to pull branch $branch"
            return 1
        }
        print_success "Repository updated to $branch"
    fi
    
    # Show verified git info so user can confirm what was pulled
    cd "$CLONE_DIR"
    local git_branch=$(git rev-parse --abbrev-ref HEAD)
    local git_commit=$(git rev-parse --short HEAD)
    local git_date=$(git log -1 --format=%cd --date=short)
    local git_msg=$(git log -1 --format=%s | cut -c1-50)
    echo -e "        ${BOLD}Source Verification${NC}"
    echo -e "        Branch:  ${CYAN}${git_branch}${NC}"
    echo -e "        Commit:  ${CYAN}${git_commit}${NC} ${DIM}(${git_date})${NC}"
    echo -e "        Message: ${DIM}${git_msg}...${NC}"
    echo ""
    
    # Step 3: Run upstream upgrade (Repeater + Core via pip)
    ((step_num++)) || true
    print_step $step_num $total_steps "Running pyMC_Repeater upgrade (includes pyMC Core)"
    
    # This runs upstream's manage.sh upgrade with our fake dialog to bypass TUI
    # Upstream handles: stopping service, updating files, pip install, config merge, starting service
    run_upstream_installer "upgrade" "$branch" || {
        print_error "Upstream upgrade failed"
        return 1
    }
    
    # Step 4: Apply log level API patch and update dashboard
    ((step_num++)) || true
    print_step $step_num $total_steps "Updating dashboard & log level API"
    
    # Apply single patch: POST /api/set_log_level endpoint for Logs page toggle
    # Will be removed once upstream merges this feature
    patch_log_level_api "$INSTALL_DIR"

    # Ensure --log-level DEBUG
    if [ -f /etc/systemd/system/pymc-repeater.service ]; then
        if ! grep -q '\-\-log-level DEBUG' /etc/systemd/system/pymc-repeater.service; then
            sed -i 's|--config /etc/pymc_repeater/config.yaml$|--config /etc/pymc_repeater/config.yaml --log-level DEBUG|' \
                /etc/systemd/system/pymc-repeater.service
            systemctl daemon-reload
            print_success "Added --log-level DEBUG for RX timing fix"
        fi
    fi
    
    # Update dashboard from GitHub Releases
    install_static_frontend || {
        print_warning "Dashboard update failed - service will continue with existing UI"
    }
    
    # Step 5: Restart service with patches
    ((step_num++)) || true
    print_step $step_num $total_steps "Restarting service"
    
    systemctl restart "$BACKEND_SERVICE" 2>/dev/null || true
    sleep 2
    
    if backend_running; then
        print_success "Service running"
    else
        print_warning "Service may need configuration"
    fi
    
    # Show completion with version details (all components)
    local new_repeater_ver=$(get_repeater_version)
    local new_core_ver=$(get_core_version)
    local new_console_ver=$(get_console_version)
    local ip_address=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    
    echo ""
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}  Full Upgrade Complete!${NC}"
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    # Get branch info from the updated clone
    local core_branch=$(get_core_branch_from_toml "$CLONE_DIR")
    local repeater_branch=$(get_repeater_branch)
    
    echo -e "  ${BOLD}Versions:${NC}"
    echo -e "  ${CHECK} pyMC Core:     ${DIM}v${current_core_ver}${NC} → ${CYAN}v${new_core_ver}${NC}  ${DIM}@${core_branch}${NC}"
    echo -e "  ${CHECK} pyMC Repeater: ${DIM}v${current_repeater_ver}${NC} → ${CYAN}v${new_repeater_ver}${NC}  ${DIM}@${repeater_branch}${NC}"
    echo -e "  ${CHECK} pyMC Console:  ${DIM}${current_console_ver}${NC} → ${CYAN}${new_console_ver}${NC}"
    echo ""
    echo -e "  ${CHECK} Configuration preserved"
    echo -e "  ${CHECK} Dashboard: ${CYAN}http://$ip_address:8000${NC}"
    echo ""
}

# ============================================================================
# Terminal-based Radio Configuration (for install flow)
# ============================================================================

configure_radio_terminal() {
    local config_file="$CONFIG_DIR/config.yaml"
    
    if [ ! -f "$config_file" ]; then
        print_warning "Config file not found, skipping radio configuration"
        return 0
    fi
    
    # Node name
    local current_name=$(yq '.repeater.node_name' "$config_file" 2>/dev/null || echo "mesh-repeater")
    local random_suffix=$(printf "%04d" $((RANDOM % 10000)))
    local default_name="pyRpt${random_suffix}"
    
    if [ "$current_name" = "mesh-repeater-01" ] || [ "$current_name" = "mesh-repeater" ]; then
        current_name="$default_name"
    fi
    
    echo -e "  ${BOLD}Node Name${NC}"
    read -p "  Enter repeater name [$current_name]: " node_name
    node_name=${node_name:-$current_name}
    yq -i ".repeater.node_name = \"$node_name\"" "$config_file"
    print_success "Node name: $node_name"
    echo ""
    
    # Radio preset selection
    echo -e "  ${BOLD}Radio Preset${NC}"
    echo -e "  ${DIM}Select a preset or choose custom to enter manual values${NC}"
    echo ""
    
    # Fetch presets from API or local files
    local presets_json=""
    presets_json=$(curl -s --max-time 5 https://api.meshcore.nz/api/v1/config 2>/dev/null)
    
    if [ -z "$presets_json" ]; then
        if [ -f "$CONSOLE_DIR/radio-presets.json" ]; then
            presets_json=$(cat "$CONSOLE_DIR/radio-presets.json")
        elif [ -f "$REPEATER_DIR/radio-presets.json" ]; then
            presets_json=$(cat "$REPEATER_DIR/radio-presets.json")
        fi
    fi
    
    local preset_count=0
    local preset_titles=()
    local preset_freqs=()
    local preset_sfs=()
    local preset_bws=()
    local preset_crs=()
    
    if [ -n "$presets_json" ]; then
        while IFS= read -r line; do
            local title=$(echo "$line" | jq -r '.title')
            local freq=$(echo "$line" | jq -r '.frequency')
            local sf=$(echo "$line" | jq -r '.spreading_factor')
            local bw=$(echo "$line" | jq -r '.bandwidth')
            local cr=$(echo "$line" | jq -r '.coding_rate')
            
            if [ -n "$title" ] && [ "$title" != "null" ]; then
                ((preset_count++)) || true
                preset_titles+=("$title")
                preset_freqs+=("$freq")
                preset_sfs+=("$sf")
                preset_bws+=("$bw")
                preset_crs+=("$cr")
                echo -e "  ${CYAN}$preset_count)${NC} $title ${DIM}(${freq}MHz SF$sf BW${bw}kHz)${NC}"
            fi
        done < <(echo "$presets_json" | jq -c '.[]' 2>/dev/null)
    fi
    
    # If no presets loaded, show fallback options with descriptions
    if [ $preset_count -eq 0 ]; then
        echo -e "  ${YELLOW}Could not fetch presets from API. Showing common options:${NC}"
        echo ""
        # Fallback presets - matches upstream api.meshcore.nz/api/v1/config + WestCoastMesh
        preset_titles=("USA/Canada (Recommended)" "Australia" "EU/UK (Long Range)" "EU/UK (Narrow)" "New Zealand" "New Zealand (Narrow)" "WestCoastMesh US")
        preset_freqs=("910.525" "915.800" "869.525" "869.618" "917.375" "917.375" "927.875")
        preset_sfs=("7" "10" "11" "8" "11" "7" "7")
        preset_bws=("62.5" "250" "250" "62.5" "250" "62.5" "62.5")
        preset_crs=("5" "5" "5" "8" "5" "5" "5")
        preset_count=${#preset_titles[@]}
        
        echo -e "  ${CYAN}1)${NC} USA/Canada        ${DIM}(910.525MHz SF7 BW62.5kHz CR5 - Recommended)${NC}"
        echo -e "  ${CYAN}2)${NC} Australia         ${DIM}(915.800MHz SF10 BW250kHz CR5)${NC}"
        echo -e "  ${CYAN}3)${NC} EU/UK Long Range  ${DIM}(869.525MHz SF11 BW250kHz CR5)${NC}"
        echo -e "  ${CYAN}4)${NC} EU/UK Narrow      ${DIM}(869.618MHz SF8 BW62.5kHz CR8)${NC}"
        echo -e "  ${CYAN}5)${NC} New Zealand       ${DIM}(917.375MHz SF11 BW250kHz CR5)${NC}"
        echo -e "  ${CYAN}6)${NC} New Zealand Narrow ${DIM}(917.375MHz SF7 BW62.5kHz CR5)${NC}"
        echo -e "  ${CYAN}7)${NC} WestCoastMesh US  ${DIM}(927.875MHz SF7 BW62.5kHz CR5 - SoCal optimized)${NC}"
    fi
    
    echo -e "  ${CYAN}C)${NC} Custom ${DIM}(enter values manually)${NC}"
    echo ""
    
    read -p "  Select preset [1-$preset_count] or C for custom: " preset_choice
    
    local freq_mhz bw_khz sf cr
    
    if [[ "$preset_choice" =~ ^[Cc]$ ]]; then
        # Custom values
        echo ""
        echo -e "  ${BOLD}Custom Radio Settings${NC}"
        
        local current_freq=$(yq '.radio.frequency' "$config_file" 2>/dev/null || echo "869618000")
        local current_freq_mhz=$(awk "BEGIN {printf \"%.3f\", $current_freq / 1000000}")
        read -p "  Frequency in MHz [$current_freq_mhz]: " freq_mhz
        freq_mhz=${freq_mhz:-$current_freq_mhz}
        
        local current_sf=$(yq '.radio.spreading_factor' "$config_file" 2>/dev/null || echo "8")
        read -p "  Spreading Factor (7-12) [$current_sf]: " sf
        sf=${sf:-$current_sf}
        
        local current_bw=$(yq '.radio.bandwidth' "$config_file" 2>/dev/null || echo "62500")
        local current_bw_khz=$(awk "BEGIN {printf \"%.1f\", $current_bw / 1000}")
        read -p "  Bandwidth in kHz [$current_bw_khz]: " bw_khz
        bw_khz=${bw_khz:-$current_bw_khz}
        
        local current_cr=$(yq '.radio.coding_rate' "$config_file" 2>/dev/null || echo "8")
        read -p "  Coding Rate (5-8) [$current_cr]: " cr
        cr=${cr:-$current_cr}
        
        # Apply custom settings
        local freq_hz=$(awk "BEGIN {printf \"%.0f\", $freq_mhz * 1000000}")
        local bw_hz=$(awk "BEGIN {printf \"%.0f\", $bw_khz * 1000}")
        
        yq -i ".radio.frequency = $freq_hz" "$config_file"
        yq -i ".radio.spreading_factor = $sf" "$config_file"
        yq -i ".radio.bandwidth = $bw_hz" "$config_file"
        yq -i ".radio.coding_rate = $cr" "$config_file"
        
        echo ""
        print_success "Radio: ${freq_mhz}MHz SF$sf BW${bw_khz}kHz CR$cr"
    elif [[ "$preset_choice" =~ ^[0-9]+$ ]] && [ "$preset_choice" -ge 1 ] && [ "$preset_choice" -le "$preset_count" ]; then
        # Use preset
        local idx=$((preset_choice - 1))
        freq_mhz="${preset_freqs[$idx]}"
        sf="${preset_sfs[$idx]}"
        bw_khz="${preset_bws[$idx]}"
        cr="${preset_crs[$idx]}"
        print_success "Using preset: ${preset_titles[$idx]}"
        
        # Apply settings
        local freq_hz=$(awk "BEGIN {printf \"%.0f\", $freq_mhz * 1000000}")
        local bw_hz=$(awk "BEGIN {printf \"%.0f\", $bw_khz * 1000}")
        
        yq -i ".radio.frequency = $freq_hz" "$config_file"
        yq -i ".radio.spreading_factor = $sf" "$config_file"
        yq -i ".radio.bandwidth = $bw_hz" "$config_file"
        yq -i ".radio.coding_rate = $cr" "$config_file"
        
        echo ""
        print_success "Radio: ${freq_mhz}MHz SF$sf BW${bw_khz}kHz CR$cr"
    else
        print_warning "Invalid selection, keeping current radio settings"
    fi
    
    # Hardware selection (before TX power so user can override hardware default)
    echo ""
    echo -e "  ${BOLD}Hardware Selection${NC}"
    echo -e "  ${DIM}Select your LoRa hardware for GPIO configuration${NC}"
    echo ""
    
    configure_hardware_terminal "$config_file"
    
    # TX Power (after hardware selection so user's choice takes precedence)
    echo -e "  ${BOLD}TX Power${NC}"
    local current_power=$(yq '.radio.tx_power' "$config_file" 2>/dev/null || echo "22")
    read -p "  TX Power in dBm [$current_power]: " tx_power
    tx_power=${tx_power:-$current_power}
    yq -i ".radio.tx_power = $tx_power" "$config_file"
    print_success "TX Power: ${tx_power}dBm"
    echo ""
}

# Terminal-based hardware/GPIO configuration
configure_hardware_terminal() {
    local config_file="${1:-$CONFIG_DIR/config.yaml}"
    local hw_config=""
    
    # Find hardware presets file
    if [ -f "$CONSOLE_DIR/radio-settings.json" ]; then
        hw_config="$CONSOLE_DIR/radio-settings.json"
    elif [ -f "$REPEATER_DIR/radio-settings.json" ]; then
        hw_config="$REPEATER_DIR/radio-settings.json"
    fi
    
    if [ -z "$hw_config" ] || [ ! -f "$hw_config" ]; then
        print_warning "Hardware presets not found, skipping GPIO configuration"
        print_info "Configure GPIO manually with: ./manage.sh gpio"
        return 0
    fi
    
    # Build hardware options
    local hw_count=0
    local hw_keys=()
    local hw_names=()
    
    while IFS= read -r key; do
        local name=$(jq -r ".hardware.\"$key\".name" "$hw_config" 2>/dev/null)
        if [ -n "$name" ] && [ "$name" != "null" ]; then
            ((hw_count++)) || true
            hw_keys+=("$key")
            hw_names+=("$name")
            echo -e "  ${CYAN}$hw_count)${NC} $name"
        fi
    done < <(jq -r '.hardware | keys[]' "$hw_config" 2>/dev/null)
    
    echo -e "  ${CYAN}C)${NC} Custom GPIO ${DIM}(enter pins manually)${NC}"
    echo ""
    
    read -p "  Select hardware [1-$hw_count] or C for custom: " hw_choice
    
    if [[ "$hw_choice" =~ ^[Cc]$ ]]; then
        # Custom GPIO
        echo ""
        echo -e "  ${BOLD}Custom GPIO Configuration${NC} ${YELLOW}(BCM pin numbering)${NC}"
        
        local current_cs=$(yq '.sx1262.cs_pin' "$config_file" 2>/dev/null || echo "21")
        read -p "  Chip Select pin [$current_cs]: " cs_pin
        cs_pin=${cs_pin:-$current_cs}
        
        local current_reset=$(yq '.sx1262.reset_pin' "$config_file" 2>/dev/null || echo "18")
        read -p "  Reset pin [$current_reset]: " reset_pin
        reset_pin=${reset_pin:-$current_reset}
        
        local current_busy=$(yq '.sx1262.busy_pin' "$config_file" 2>/dev/null || echo "20")
        read -p "  Busy pin [$current_busy]: " busy_pin
        busy_pin=${busy_pin:-$current_busy}
        
        local current_irq=$(yq '.sx1262.irq_pin' "$config_file" 2>/dev/null || echo "16")
        read -p "  IRQ pin [$current_irq]: " irq_pin
        irq_pin=${irq_pin:-$current_irq}
        
        local current_txen=$(yq '.sx1262.txen_pin' "$config_file" 2>/dev/null || echo "-1")
        read -p "  TX Enable pin (-1 to disable) [$current_txen]: " txen_pin
        txen_pin=${txen_pin:-$current_txen}
        
        local current_rxen=$(yq '.sx1262.rxen_pin' "$config_file" 2>/dev/null || echo "-1")
        read -p "  RX Enable pin (-1 to disable) [$current_rxen]: " rxen_pin
        rxen_pin=${rxen_pin:-$current_rxen}
        
        # Apply custom GPIO
        yq -i ".sx1262.cs_pin = $cs_pin" "$config_file"
        yq -i ".sx1262.reset_pin = $reset_pin" "$config_file"
        yq -i ".sx1262.busy_pin = $busy_pin" "$config_file"
        yq -i ".sx1262.irq_pin = $irq_pin" "$config_file"
        yq -i ".sx1262.txen_pin = $txen_pin" "$config_file"
        yq -i ".sx1262.rxen_pin = $rxen_pin" "$config_file"
        
        echo ""
        print_success "Custom GPIO: CS=$cs_pin RST=$reset_pin BUSY=$busy_pin IRQ=$irq_pin"
        
    elif [[ "$hw_choice" =~ ^[0-9]+$ ]] && [ "$hw_choice" -ge 1 ] && [ "$hw_choice" -le "$hw_count" ]; then
        # Use preset
        local idx=$((hw_choice - 1))
        local hw_key="${hw_keys[$idx]}"
        local hw_name="${hw_names[$idx]}"
        local preset=$(jq ".hardware.\"$hw_key\"" "$hw_config" 2>/dev/null)
        
        if [ -n "$preset" ] && [ "$preset" != "null" ]; then
            # Extract all GPIO settings
            local bus_id=$(echo "$preset" | jq -r '.bus_id // 0')
            local cs_id=$(echo "$preset" | jq -r '.cs_id // 0')
            local cs_pin=$(echo "$preset" | jq -r '.cs_pin // 21')
            local reset_pin=$(echo "$preset" | jq -r '.reset_pin // 18')
            local busy_pin=$(echo "$preset" | jq -r '.busy_pin // 20')
            local irq_pin=$(echo "$preset" | jq -r '.irq_pin // 16')
            local txen_pin=$(echo "$preset" | jq -r '.txen_pin // -1')
            local rxen_pin=$(echo "$preset" | jq -r '.rxen_pin // -1')
            local is_waveshare=$(echo "$preset" | jq -r '.is_waveshare // false')
            local use_dio3_tcxo=$(echo "$preset" | jq -r '.use_dio3_tcxo // false')
            local tx_power=$(echo "$preset" | jq -r '.tx_power // 22')
            local preamble_length=$(echo "$preset" | jq -r '.preamble_length // 17')
            
            # Apply to config
            yq -i ".sx1262.bus_id = $bus_id" "$config_file"
            yq -i ".sx1262.cs_id = $cs_id" "$config_file"
            yq -i ".sx1262.cs_pin = $cs_pin" "$config_file"
            yq -i ".sx1262.reset_pin = $reset_pin" "$config_file"
            yq -i ".sx1262.busy_pin = $busy_pin" "$config_file"
            yq -i ".sx1262.irq_pin = $irq_pin" "$config_file"
            yq -i ".sx1262.txen_pin = $txen_pin" "$config_file"
            yq -i ".sx1262.rxen_pin = $rxen_pin" "$config_file"
            yq -i ".sx1262.is_waveshare = $is_waveshare" "$config_file"
            yq -i ".sx1262.use_dio3_tcxo = $use_dio3_tcxo" "$config_file"
            # Note: tx_power is set as default but user can override in next step
            yq -i ".radio.tx_power = $tx_power" "$config_file"
            yq -i ".radio.preamble_length = $preamble_length" "$config_file"
            
            echo ""
            print_success "Hardware: $hw_name"
            print_success "GPIO: CS=$cs_pin RST=$reset_pin BUSY=$busy_pin IRQ=$irq_pin"
            if [ "$txen_pin" != "-1" ]; then
                print_info "TX/RX Enable: TXEN=$txen_pin RXEN=$rxen_pin"
            fi
            print_info "Default TX Power: ${tx_power}dBm (you can change this next)"
        fi
    else
        print_warning "Invalid selection, keeping current GPIO settings"
        print_info "Configure GPIO later with: ./manage.sh gpio"
    fi
    
    echo ""
}

# ============================================================================
# Settings Function (Radio Configuration) - TUI version for manage.sh menu
# ============================================================================

do_settings() {
    if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
        show_error "Configuration file not found!\n\nPlease install pyMC Console first."
        return 1
    fi
    
    while true; do
        local current_name=$(yq '.repeater.node_name' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "unknown")
        local current_freq=$(yq '.radio.frequency' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "0")
        local current_freq_mhz=$(awk "BEGIN {printf \"%.3f\", $current_freq / 1000000}")
        local current_sf=$(yq '.radio.spreading_factor' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "0")
        local current_bw=$(yq '.radio.bandwidth' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "0")
        local current_bw_khz=$(awk "BEGIN {printf \"%.1f\", $current_bw / 1000}")
        local current_power=$(yq '.radio.tx_power' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "0")
        
        CHOICE=$($DIALOG --backtitle "pyMC Console Management" --title "Radio Settings" --menu "\nCurrent Configuration:\n  Name: $current_name\n  Freq: ${current_freq_mhz}MHz | SF$current_sf | BW${current_bw_khz}kHz | ${current_power}dBm\n\nSelect setting to change:" 20 70 8 \
            "name" "Node name ($current_name)" \
            "preset" "Load radio preset (frequency, SF, BW, CR)" \
            "frequency" "Frequency (${current_freq_mhz}MHz)" \
            "power" "TX Power (${current_power}dBm)" \
            "spreading" "Spreading Factor (SF$current_sf)" \
            "bandwidth" "Bandwidth (${current_bw_khz}kHz)" \
            "apply" "Apply changes and restart" \
            "back" "Back to main menu" 3>&1 1>&2 2>&3)
        
        case $CHOICE in
            "name")
                local new_name=$(get_input "Node Name" "Enter repeater node name:" "$current_name")
                if [ -n "$new_name" ]; then
                    yq -i ".repeater.node_name = \"$new_name\"" "$CONFIG_DIR/config.yaml"
                    show_info "Updated" "Node name set to: $new_name"
                fi
                ;;
            "preset")
                select_radio_preset
                ;;
            "frequency")
                local new_freq=$(get_input "Frequency" "Enter frequency in MHz (e.g., 869.618):" "$current_freq_mhz")
                if [ -n "$new_freq" ]; then
                    local freq_hz=$(awk "BEGIN {printf \"%.0f\", $new_freq * 1000000}")
                    yq -i ".radio.frequency = $freq_hz" "$CONFIG_DIR/config.yaml"
                    show_info "Updated" "Frequency set to: ${new_freq}MHz"
                fi
                ;;
            "power")
                local new_power=$(get_input "TX Power" "Enter TX power in dBm (e.g., 14):" "$current_power")
                if [ -n "$new_power" ]; then
                    yq -i ".radio.tx_power = $new_power" "$CONFIG_DIR/config.yaml"
                    show_info "Updated" "TX Power set to: ${new_power}dBm"
                fi
                ;;
            "spreading")
                local new_sf=$(get_input "Spreading Factor" "Enter spreading factor (7-12):" "$current_sf")
                if [ -n "$new_sf" ]; then
                    yq -i ".radio.spreading_factor = $new_sf" "$CONFIG_DIR/config.yaml"
                    show_info "Updated" "Spreading factor set to: SF$new_sf"
                fi
                ;;
            "bandwidth")
                local new_bw=$(get_input "Bandwidth" "Enter bandwidth in kHz (e.g., 62.5):" "$current_bw_khz")
                if [ -n "$new_bw" ]; then
                    local bw_hz=$(awk "BEGIN {printf \"%.0f\", $new_bw * 1000}")
                    yq -i ".radio.bandwidth = $bw_hz" "$CONFIG_DIR/config.yaml"
                    show_info "Updated" "Bandwidth set to: ${new_bw}kHz"
                fi
                ;;
            "apply")
                if [ "$EUID" -eq 0 ]; then
                    systemctl restart "$BACKEND_SERVICE" 2>/dev/null || true
                    sleep 2
                    if backend_running; then
                        show_info "Applied" "Configuration applied and service restarted successfully!"
                    else
                        show_error "Service failed to restart!\n\nCheck logs: journalctl -u $BACKEND_SERVICE"
                    fi
                else
                    show_info "Note" "Run as root to restart services automatically.\n\nManually restart with:\nsudo systemctl restart $BACKEND_SERVICE"
                fi
                ;;
            "back"|"")
                return 0
                ;;
        esac
    done
}

select_radio_preset() {
    # Fetch presets from API or use local file
    local presets_json=""
    
    echo "Fetching radio presets..." >&2
    presets_json=$(curl -s --max-time 5 https://api.meshcore.nz/api/v1/config 2>/dev/null)
    
    if [ -z "$presets_json" ]; then
        if [ -f "$CONSOLE_DIR/radio-presets.json" ]; then
            presets_json=$(cat "$CONSOLE_DIR/radio-presets.json")
        elif [ -f "$REPEATER_DIR/radio-presets.json" ]; then
            presets_json=$(cat "$REPEATER_DIR/radio-presets.json")
        else
            show_error "Could not fetch radio presets from API and no local file found."
            return 1
        fi
    fi
    
    # Build menu from presets
    local menu_items=()
    local index=1
    
    while IFS= read -r line; do
        local title=$(echo "$line" | jq -r '.title')
        local freq=$(echo "$line" | jq -r '.frequency')
        local sf=$(echo "$line" | jq -r '.spreading_factor')
        local bw=$(echo "$line" | jq -r '.bandwidth')
        menu_items+=("$index" "$title (${freq}MHz SF$sf BW$bw)")
        ((index++)) || true
    done < <(echo "$presets_json" | jq -c '.[]' 2>/dev/null)
    
    if [ ${#menu_items[@]} -eq 0 ]; then
        show_error "No presets found in configuration."
        return 1
    fi
    
    local selection=$($DIALOG --backtitle "pyMC Console Management" --title "Radio Presets" --menu "Select a radio preset:" 20 70 10 "${menu_items[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$selection" ]; then
        local preset=$(echo "$presets_json" | jq -c ".[$((selection-1))]" 2>/dev/null)
        
        if [ -n "$preset" ] && [ "$preset" != "null" ]; then
            local freq=$(echo "$preset" | jq -r '.frequency')
            local sf=$(echo "$preset" | jq -r '.spreading_factor')
            local bw=$(echo "$preset" | jq -r '.bandwidth')
            local cr=$(echo "$preset" | jq -r '.coding_rate')
            local title=$(echo "$preset" | jq -r '.title')
            
            local freq_hz=$(awk "BEGIN {printf \"%.0f\", $freq * 1000000}")
            local bw_hz=$(awk "BEGIN {printf \"%.0f\", $bw * 1000}")
            
            yq -i ".radio.frequency = $freq_hz" "$CONFIG_DIR/config.yaml"
            yq -i ".radio.spreading_factor = $sf" "$CONFIG_DIR/config.yaml"
            yq -i ".radio.bandwidth = $bw_hz" "$CONFIG_DIR/config.yaml"
            yq -i ".radio.coding_rate = $cr" "$CONFIG_DIR/config.yaml"
            
            show_info "Preset Applied" "Applied preset: $title\n\nFrequency: ${freq}MHz\nSpreading Factor: SF$sf\nBandwidth: ${bw}kHz\nCoding Rate: $cr\n\nRemember to apply changes to restart the service."
        fi
    fi
}

# ============================================================================
# GPIO Function (Advanced Hardware Configuration)
# ============================================================================

do_gpio() {
    # Show warning first
    if ! ask_yes_no "⚠️  Advanced Configuration" "\nWARNING: GPIO Configuration\n\nThese settings are for ADVANCED USERS ONLY.\n\nIncorrect GPIO settings can:\n- Prevent radio communication\n- Cause hardware damage\n- Make the repeater non-functional\n\nOnly proceed if you know your hardware pinout!\n\nContinue?"; then
        return 0
    fi
    
    if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
        show_error "Configuration file not found!\n\nPlease install pyMC Console first."
        return 1
    fi
    
    while true; do
        # Read current GPIO settings
        local cs_pin=$(yq '.sx1262.cs_pin' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "-1")
        local reset_pin=$(yq '.sx1262.reset_pin' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "-1")
        local busy_pin=$(yq '.sx1262.busy_pin' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "-1")
        local irq_pin=$(yq '.sx1262.irq_pin' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "-1")
        local txen_pin=$(yq '.sx1262.txen_pin' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "-1")
        local rxen_pin=$(yq '.sx1262.rxen_pin' "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "-1")
        
        CHOICE=$($DIALOG --backtitle "pyMC Console Management" --title "GPIO Configuration ⚠️" --menu "\nCurrent GPIO Pins (BCM numbering):\n  CS: $cs_pin | Reset: $reset_pin | Busy: $busy_pin\n  IRQ: $irq_pin | TXEN: $txen_pin | RXEN: $rxen_pin\n\nSelect option:" 20 70 8 \
            "preset" "Load hardware preset" \
            "cs" "Chip Select pin ($cs_pin)" \
            "reset" "Reset pin ($reset_pin)" \
            "busy" "Busy pin ($busy_pin)" \
            "irq" "IRQ pin ($irq_pin)" \
            "txen" "TX Enable pin ($txen_pin, -1=disabled)" \
            "rxen" "RX Enable pin ($rxen_pin, -1=disabled)" \
            "apply" "Apply changes and restart" \
            "back" "Back to main menu" 3>&1 1>&2 2>&3)
        
        case $CHOICE in
            "preset")
                select_hardware_preset
                ;;
            "cs")
                local new_pin=$(get_input "Chip Select Pin" "Enter CS pin (BCM numbering):" "$cs_pin")
                [ -n "$new_pin" ] && yq -i ".sx1262.cs_pin = $new_pin" "$CONFIG_DIR/config.yaml"
                ;;
            "reset")
                local new_pin=$(get_input "Reset Pin" "Enter Reset pin (BCM numbering):" "$reset_pin")
                [ -n "$new_pin" ] && yq -i ".sx1262.reset_pin = $new_pin" "$CONFIG_DIR/config.yaml"
                ;;
            "busy")
                local new_pin=$(get_input "Busy Pin" "Enter Busy pin (BCM numbering):" "$busy_pin")
                [ -n "$new_pin" ] && yq -i ".sx1262.busy_pin = $new_pin" "$CONFIG_DIR/config.yaml"
                ;;
            "irq")
                local new_pin=$(get_input "IRQ Pin" "Enter IRQ pin (BCM numbering):" "$irq_pin")
                [ -n "$new_pin" ] && yq -i ".sx1262.irq_pin = $new_pin" "$CONFIG_DIR/config.yaml"
                ;;
            "txen")
                local new_pin=$(get_input "TX Enable Pin" "Enter TXEN pin (-1 to disable):" "$txen_pin")
                [ -n "$new_pin" ] && yq -i ".sx1262.txen_pin = $new_pin" "$CONFIG_DIR/config.yaml"
                ;;
            "rxen")
                local new_pin=$(get_input "RX Enable Pin" "Enter RXEN pin (-1 to disable):" "$rxen_pin")
                [ -n "$new_pin" ] && yq -i ".sx1262.rxen_pin = $new_pin" "$CONFIG_DIR/config.yaml"
                ;;
            "apply")
                if [ "$EUID" -eq 0 ]; then
                    systemctl restart "$BACKEND_SERVICE" 2>/dev/null || true
                    sleep 2
                    if backend_running; then
                        show_info "Applied" "GPIO configuration applied and service restarted!"
                    else
                        show_error "Service failed to restart!\n\nGPIO settings may be incorrect.\nCheck logs: journalctl -u $BACKEND_SERVICE"
                    fi
                else
                    show_info "Note" "Run as root to restart services automatically."
                fi
                ;;
            "back"|"")
                return 0
                ;;
        esac
    done
}

select_hardware_preset() {
    local hw_config=""
    
    if [ -f "$CONSOLE_DIR/radio-settings.json" ]; then
        hw_config="$CONSOLE_DIR/radio-settings.json"
    elif [ -f "$REPEATER_DIR/radio-settings.json" ]; then
        hw_config="$REPEATER_DIR/radio-settings.json"
    else
        show_error "Hardware configuration file not found!"
        return 1
    fi
    
    # Build menu from hardware presets
    local menu_items=()
    
    # Use keys_unsorted to preserve JSON insertion order (matches upstream grep-based parsing)
    while IFS= read -r key; do
        local name=$(jq -r ".hardware.\"$key\".name" "$hw_config")
        menu_items+=("$key" "$name")
    done < <(jq -r '.hardware | keys_unsorted[]' "$hw_config" 2>/dev/null)
    
    if [ ${#menu_items[@]} -eq 0 ]; then
        show_error "No hardware presets found."
        return 1
    fi
    
    local selection=$($DIALOG --backtitle "pyMC Console Management" --title "Hardware Presets" --menu "Select your hardware:" 20 70 10 "${menu_items[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$selection" ]; then
        local preset=$(jq ".hardware.\"$selection\"" "$hw_config" 2>/dev/null)
        
        if [ -n "$preset" ] && [ "$preset" != "null" ]; then
            # Apply all GPIO settings from preset
            local bus_id=$(echo "$preset" | jq -r '.bus_id // 0')
            local cs_id=$(echo "$preset" | jq -r '.cs_id // 0')
            local cs_pin=$(echo "$preset" | jq -r '.cs_pin // 21')
            local reset_pin=$(echo "$preset" | jq -r '.reset_pin // 18')
            local busy_pin=$(echo "$preset" | jq -r '.busy_pin // 20')
            local irq_pin=$(echo "$preset" | jq -r '.irq_pin // 16')
            local txen_pin=$(echo "$preset" | jq -r '.txen_pin // -1')
            local rxen_pin=$(echo "$preset" | jq -r '.rxen_pin // -1')
            local is_waveshare=$(echo "$preset" | jq -r '.is_waveshare // false')
            local use_dio3_tcxo=$(echo "$preset" | jq -r '.use_dio3_tcxo // false')
            local tx_power=$(echo "$preset" | jq -r '.tx_power // 14')
            
            yq -i ".sx1262.bus_id = $bus_id" "$CONFIG_DIR/config.yaml"
            yq -i ".sx1262.cs_id = $cs_id" "$CONFIG_DIR/config.yaml"
            yq -i ".sx1262.cs_pin = $cs_pin" "$CONFIG_DIR/config.yaml"
            yq -i ".sx1262.reset_pin = $reset_pin" "$CONFIG_DIR/config.yaml"
            yq -i ".sx1262.busy_pin = $busy_pin" "$CONFIG_DIR/config.yaml"
            yq -i ".sx1262.irq_pin = $irq_pin" "$CONFIG_DIR/config.yaml"
            yq -i ".sx1262.txen_pin = $txen_pin" "$CONFIG_DIR/config.yaml"
            yq -i ".sx1262.rxen_pin = $rxen_pin" "$CONFIG_DIR/config.yaml"
            yq -i ".sx1262.is_waveshare = $is_waveshare" "$CONFIG_DIR/config.yaml"
            yq -i ".sx1262.use_dio3_tcxo = $use_dio3_tcxo" "$CONFIG_DIR/config.yaml"
            yq -i ".radio.tx_power = $tx_power" "$CONFIG_DIR/config.yaml"
            
            local name=$(echo "$preset" | jq -r '.name')
            show_info "Preset Applied" "Applied hardware preset: $name\n\nGPIO Pins:\n  CS: $cs_pin | Reset: $reset_pin\n  Busy: $busy_pin | IRQ: $irq_pin\n  TXEN: $txen_pin | RXEN: $rxen_pin\n\nTX Power: ${tx_power}dBm\n\nRemember to apply changes to restart."
        fi
    fi
}

# ============================================================================
# Service Control Functions
# ============================================================================

do_start() {
    if [ "$EUID" -ne 0 ]; then
        show_error "Service control requires root privileges.\n\nPlease run: sudo $0 start"
        return 1
    fi
    
    echo "Starting service..."
    systemctl start "$BACKEND_SERVICE" 2>/dev/null || true
    sleep 2
    
    local status="✗"
    backend_running && status="✓"
    
    show_info "Service Started" "\npyMC Repeater: $status\n\nDashboard: http://$(hostname -I | awk '{print $1}'):8000/"
}

do_stop() {
    if [ "$EUID" -ne 0 ]; then
        show_error "Service control requires root privileges.\n\nPlease run: sudo $0 stop"
        return 1
    fi
    
    echo "Stopping service..."
    systemctl stop "$BACKEND_SERVICE" 2>/dev/null || true
    
    show_info "Service Stopped" "\n✓ pyMC Repeater service has been stopped."
}

do_restart() {
    if [ "$EUID" -ne 0 ]; then
        show_error "Service control requires root privileges.\n\nPlease run: sudo $0 restart"
        return 1
    fi
    
    echo "Restarting service..."
    systemctl restart "$BACKEND_SERVICE" 2>/dev/null || true
    sleep 2
    
    local status="✗"
    backend_running && status="✓"
    
    show_info "Service Restarted" "\npyMC Repeater: $status\n\nDashboard: http://$(hostname -I | awk '{print $1}'):8000/"
}

# ============================================================================
# Uninstall Function
# ============================================================================

do_uninstall() {
    # Get site-packages path for checking leftovers
    local site_packages
    site_packages=$(python3 -c "import site; print(site.getsitepackages()[0])" 2>/dev/null || echo "/usr/local/lib/python3/dist-packages")
    
    # Check for ANY installation (old paths, new paths, or site-packages leftovers)
    local found_install=false
    [ -d "$INSTALL_DIR" ] && found_install=true
    [ -d "$CONSOLE_DIR" ] && found_install=true
    [ -d "/opt/pymc_console/pymc_repeater" ] && found_install=true  # Old path
    [ -f "/etc/systemd/system/pymc-repeater.service" ] && found_install=true
    [ -d "$site_packages/repeater" ] && found_install=true  # pip leftovers
    [ -d "$site_packages/pymc_core" ] && found_install=true  # pip leftovers
    
    if [ "$found_install" = false ]; then
        show_error "pyMC Console is not installed."
        return 1
    fi
    
    if [ "$EUID" -ne 0 ]; then
        show_error "Uninstall requires root privileges.\n\nPlease run: sudo $0 uninstall"
        return 1
    fi
    
    # Check if clone directory exists
    local has_clone=false
    [ -d "$CLONE_DIR" ] && has_clone=true
    
    local uninstall_msg="\nThis will COMPLETELY REMOVE:\n\n- pyMC Repeater service and files\n- pyMC Console frontend\n- Python packages (pymc_repeater, pymc_core)\n- Configuration files\n- Log files\n- Service user"
    
    if [ "$has_clone" = true ]; then
        uninstall_msg="$uninstall_msg\n\nNote: The clone at $CLONE_DIR will be kept.\nYou can remove it manually if desired."
    fi
    
    uninstall_msg="$uninstall_msg\n\nThis action cannot be undone!\n\nContinue?"
    
    if ! ask_yes_no "⚠️  Confirm Uninstall" "$uninstall_msg"; then
        return 0
    fi
    
    clear
    echo "=== pyMC Console Uninstall ==="
    echo ""
    
    # =========================================================================
    # Step 1: Run upstream uninstaller (simple - no fancy progress bar needed)
    # =========================================================================
    echo "[1/4] Removing pyMC_Repeater..."
    
    # Always do manual cleanup - it's fast and reliable
    # (upstream's uninstaller uses TUI which is complex to wrap)
    systemctl stop "$BACKEND_SERVICE" 2>/dev/null || true
    systemctl disable "$BACKEND_SERVICE" 2>/dev/null || true
    rm -f /etc/systemd/system/pymc-repeater.service
    systemctl daemon-reload
    rm -rf "$INSTALL_DIR"
    rm -rf "$CONFIG_DIR"
    rm -rf "$LOG_DIR"
    rm -rf /var/lib/pymc_repeater
    if id "$SERVICE_USER" &>/dev/null; then
        userdel "$SERVICE_USER" 2>/dev/null || true
    fi
    echo "    ✓ pyMC_Repeater removed"
    
    # =========================================================================
    # Step 2: Remove pyMC Console extras (not handled by upstream)
    # =========================================================================
    echo "[2/4] Removing pyMC Console extras..."
    rm -rf "$CONSOLE_DIR"
    rm -rf "/opt/pymc_console"  # Old path
    echo "    ✓ Console directories removed"
    
    # =========================================================================
    # Step 3: Clean up any leftover site-packages (pip leftovers)
    # =========================================================================
    echo "[3/4] Cleaning up Python packages..."
    pip uninstall -y pymc_repeater 2>/dev/null || true
    pip uninstall -y pymc_core 2>/dev/null || true
    pip uninstall -y pymc-repeater 2>/dev/null || true
    pip uninstall -y pymc-core 2>/dev/null || true
    # Remove any leftover directories
    rm -rf "$site_packages/repeater" 2>/dev/null || true
    rm -rf "$site_packages/pymc_core" 2>/dev/null || true
    rm -rf "$site_packages/pymc_repeater"* 2>/dev/null || true
    rm -rf "$site_packages/pymc_core"* 2>/dev/null || true
    echo "    ✓ Python packages cleaned"
    
    # =========================================================================
    # Step 4: Handle clone directory
    # =========================================================================
    echo "[4/4] Finalizing..."
    
    echo ""
    echo "=== Uninstall Complete ==="
    echo ""
    
    # Offer to delete clone directory
    if [ "$has_clone" = true ]; then
        if ask_yes_no "Remove Clone?" "\nThe pyMC_Repeater clone still exists at:\n$CLONE_DIR\n\nWould you like to remove it as well?"; then
            rm -rf "$CLONE_DIR"
            echo "    ✓ Clone directory removed"
        else
            echo "    Clone directory preserved at: $CLONE_DIR"
        fi
        echo ""
    fi
    
    show_info "Uninstall Complete" "\npyMC Console has been completely removed.\n\nThank you for using pyMC Console!"
}

# ============================================================================
# Helper Functions
# ============================================================================

check_spi() {
    # Skip SPI check on non-Linux systems (macOS, etc.)
    if [[ "$(uname -s)" != "Linux" ]]; then
        return 0
    fi
    
    # Check if SPI is already loaded via kernel module
    if grep -q "spi" /proc/modules 2>/dev/null; then
        return 0
    fi
    
    # Check for spidev devices (works on Ubuntu and other distros)
    if ls /dev/spidev* &>/dev/null; then
        return 0
    fi
    
    # Check if spi_bcm2835 or spi_bcm2708 modules are available (Raspberry Pi)
    if lsmod 2>/dev/null | grep -q "spi_bcm"; then
        return 0
    fi
    
    # Check if spidev module is loaded
    if lsmod 2>/dev/null | grep -q "spidev"; then
        return 0
    fi
    
    # Raspberry Pi / Ubuntu on Pi: check config.txt locations
    local config_file=""
    if [ -f "/boot/firmware/config.txt" ]; then
        # Ubuntu on Raspberry Pi uses /boot/firmware/
        config_file="/boot/firmware/config.txt"
    elif [ -f "/boot/config.txt" ]; then
        # Raspberry Pi OS uses /boot/
        config_file="/boot/config.txt"
    fi
    
    if [ -n "$config_file" ]; then
        # Raspberry Pi (any OS) - can enable via config.txt
        if grep -q "dtparam=spi=on" "$config_file" 2>/dev/null; then
            return 0
        fi
        
        if ask_yes_no "SPI Not Enabled" "\nSPI interface is required but not enabled!\n\nWould you like to enable it now?\n(This will require a reboot)"; then
            echo "dtparam=spi=on" >> "$config_file"
            show_info "SPI Enabled" "\nSPI has been enabled.\n\nSystem will reboot now.\nPlease run this script again after reboot."
            reboot
        else
            show_error "SPI is required for LoRa radio operation.\n\nPlease enable SPI manually and run this script again."
            exit 1
        fi
    else
        # Generic Linux (Ubuntu x86, other SBCs, etc.)
        # Try to load spidev module
        if modprobe spidev 2>/dev/null; then
            if ls /dev/spidev* &>/dev/null; then
                return 0
            fi
        fi
        
        # Still no SPI - warn user
        if ! ask_yes_no "SPI Check" "\nCould not verify SPI is enabled.\n\nFor LoRa radio operation, ensure SPI is enabled on your system.\n\nOn Ubuntu/Debian, you may need to:\n- Load the spidev module: sudo modprobe spidev\n- Enable SPI in device tree overlays\n- Check your hardware supports SPI\n\nContinue anyway?"; then
            exit 1
        fi
    fi
}

install_yq() {
    if ! command -v yq &> /dev/null || [[ "$(yq --version 2>&1)" != *"mikefarah/yq"* ]]; then
        echo "Installing yq..."
        install_yq_silent
    fi
}

# Silent version for use with spinner
install_yq_silent() {
    local YQ_VERSION="v4.40.5"
    local YQ_BINARY="yq_linux_arm64"
    
    if [[ "$(uname -m)" == "x86_64" ]]; then
        YQ_BINARY="yq_linux_amd64"
    elif [[ "$(uname -m)" == "armv7"* ]]; then
        YQ_BINARY="yq_linux_arm"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        YQ_BINARY="yq_darwin_arm64"
        [[ "$(uname -m)" == "x86_64" ]] && YQ_BINARY="yq_darwin_amd64"
    fi
    
    wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" && chmod +x /usr/local/bin/yq
}

# ============================================================================
# UPSTREAM INSTALLATION MANAGER
# ============================================================================
# This section handles running pyMC_Repeater's native manage.sh installer.
# We run upstream's installer directly (user sees their native TUI), then
# apply our patches and overlay our dashboard afterward.
#
# The approach:
# 1. Clone/update pyMC_Repeater to a sibling directory
# 2. Run upstream's manage.sh (install/upgrade) in foreground - user sees TUI
# 3. Apply our patches to the installed files (/opt/pymc_repeater)
# 4. Overlay our React dashboard
# 5. Run our radio configuration
#
# Note: Upstream's radio config script is temporarily renamed during install
# so we can run our own configuration flow instead.
# ============================================================================

# Run upstream's manage.sh with a specific action
# Usage: run_upstream_installer <action> [branch]
# Actions: install, upgrade
#
# Strategy: Let upstream run in foreground so user sees its native TUI.
# We skip upstream's radio config and do our own after.
run_upstream_installer() {
    local action="$1"
    local branch="${2:-$DEFAULT_BRANCH}"
    local upstream_script="$CLONE_DIR/manage.sh"
    local exit_code=0
    
    # Verify clone exists
    if [ ! -f "$upstream_script" ]; then
        print_error "Upstream manage.sh not found at $upstream_script"
        return 1
    fi
    
    # Temporarily rename setup-radio-config.sh to skip upstream's radio config
    # We run our own config after installation
    local radio_config_script="$CLONE_DIR/setup-radio-config.sh"
    local radio_config_backup=""
    if [ -f "$radio_config_script" ]; then
        radio_config_backup="${radio_config_script}.pymc_backup"
        mv "$radio_config_script" "$radio_config_backup"
    fi
    
    echo ""
    echo -e "        ${DIM}────────────────────────────────────────────────────────${NC}"
    echo -e "        ${BOLD}Running pyMC_Repeater $action...${NC}"
    echo -e "        ${DIM}You'll see the upstream installer's interface below.${NC}"
    echo -e "        ${DIM}────────────────────────────────────────────────────────${NC}"
    echo ""
    
    # Run upstream's manage.sh directly in foreground
    # User sees the native TUI (whiptail dialogs, progress bars, etc.)
    (
        cd "$CLONE_DIR"
        bash "$upstream_script" "$action"
    )
    exit_code=$?
    
    echo ""
    echo -e "        ${DIM}────────────────────────────────────────────────────────${NC}"
    
    # Restore radio config script if we backed it up
    if [ -n "$radio_config_backup" ] && [ -f "$radio_config_backup" ]; then
        mv "$radio_config_backup" "$radio_config_script"
    fi
    
    if [ $exit_code -eq 0 ]; then
        echo -e "        ${CHECK} pyMC_Repeater $action completed"
        return 0
    else
        echo -e "        ${CROSS} ${RED}pyMC_Repeater $action failed${NC}"
        return 1
    fi
}

# ============================================================================
# PATCH REGISTRY
# ============================================================================
# Minimal patches for pyMC Console. Most functionality now provided natively
# by upstream pyMC_Repeater dev branch.
#
# REMOVED (No longer needed - upstream provides natively):
# - patch_api_endpoints - Merged upstream in PR #36
# - patch_stats_api - Merged upstream in PR #36  
# - patch_logging_section - Fixed in upstream dev branch (main.py lines 535-538)
# - patch_mesh_cli - Not essential; Terminal.tsx uses /api/stats data directly
# - patch_private_key_api - Use Identity Management API (/api/identities) instead
#
# REMAINING (Pending upstream PR):
#
# 3. patch_log_level_api (api_endpoints.py)
#    - Adds POST /api/set_log_level endpoint
#    - Allows web UI to toggle log level (INFO/DEBUG) and restart service
#    - PR Status: Pending - will be removed once merged upstream
#
# NOTE: GPIO timing issue is handled by --log-level DEBUG in service file.
# ============================================================================

# ------------------------------------------------------------------------------
# PATCH 3: Log Level API Endpoint
# ------------------------------------------------------------------------------
# File: repeater/web/api_endpoints.py
# Purpose: Allow web UI to toggle log level (INFO/DEBUG) without SSH
# Changes:
#   - Add POST /api/set_log_level endpoint
#   - Updates config.yaml -> logging.level
#   - Restarts pymc-repeater service to apply change
#   - Returns success/failure
# ------------------------------------------------------------------------------
patch_log_level_api() {
    local target_dir="${1:-$CLONE_DIR}"
    local api_file="$target_dir/repeater/web/api_endpoints.py"
    
    if [ ! -f "$api_file" ]; then
        print_warning "api_endpoints.py not found, skipping log level patch"
        return 0
    fi
    
    # Check if already patched
    if grep -q 'def set_log_level' "$api_file" 2>/dev/null; then
        print_info "Log level API already patched"
        return 0
    fi
    
    # Use Python to add the endpoint
    python3 << PATCHEOF
import re

api_file = "$api_file"

with open(api_file, 'r') as f:
    content = f.read()

# Add set_log_level endpoint after update_radio_config (or save_cad_settings if radio config not present)
set_log_level_code = '''

    @cherrypy.expose
    @cherrypy.tools.json_out()
    @cherrypy.tools.json_in()
    def set_log_level(self):
        """Set log level and restart service to apply
        
        POST /api/set_log_level
        Body: {"level": "DEBUG" | "INFO" | "WARNING"}
        
        Returns: {"success": true, "data": {"level": "DEBUG", "restarting": true}}
        """
        import subprocess
        try:
            self._require_post()
            data = cherrypy.request.json or {}
            
            level = data.get("level", "").upper()
            if level not in ("DEBUG", "INFO", "WARNING", "ERROR"):
                return self._error("Invalid log level. Use DEBUG, INFO, WARNING, or ERROR")
            
            # Update config.yaml
            config_path = getattr(self, '_config_path', '/etc/pymc_repeater/config.yaml')
            
            # Ensure logging section exists
            if "logging" not in self.config:
                self.config["logging"] = {}
            self.config["logging"]["level"] = level
            
            # Save config
            self._save_config_to_file(config_path)
            
            logger.info(f"Log level changed to {level}, restarting service...")
            
            # Schedule service restart in background (so we can return response first)
            # Use subprocess.Popen to not wait for completion
            subprocess.Popen(
                ["systemctl", "restart", "pymc-repeater"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            
            return self._success({
                "level": level,
                "restarting": True,
                "message": f"Log level set to {level}. Service restarting..."
            })
            
        except cherrypy.HTTPError:
            raise
        except Exception as e:
            logger.error(f"Error setting log level: {e}")
            return self._error(str(e))
'''

# Find insertion point - after update_radio_config if it exists, otherwise after save_cad_settings
if 'def update_radio_config' in content:
    # Insert after update_radio_config
    pattern = r'(    def update_radio_config\(self\):.*?return self\._error\(str\(e\)\))'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        insert_pos = match.end()
        content = content[:insert_pos] + set_log_level_code + content[insert_pos:]
else:
    # Fall back to inserting after save_cad_settings
    pattern = r'(    def save_cad_settings\(self\):.*?return self\._error\(e\))'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        insert_pos = match.end()
        content = content[:insert_pos] + set_log_level_code + content[insert_pos:]

with open(api_file, 'w') as f:
    f.write(content)
print("Patched api_endpoints.py with set_log_level")
PATCHEOF
    
    # Verify patch was applied
    if grep -q 'def set_log_level' "$api_file" 2>/dev/null; then
        print_success "Patched api_endpoints.py with set_log_level"
    else
        print_warning "Log level API patch may not have applied correctly"
    fi
}

install_backend_service() {
    # Copy upstream's service file as base (from clone directory)
    local service_file="$CLONE_DIR/pymc-repeater.service"
    
    # Fall back to install dir if clone doesn't have it
    if [ ! -f "$service_file" ] && [ -f "$INSTALL_DIR/pymc-repeater.service" ]; then
        service_file="$INSTALL_DIR/pymc-repeater.service"
    fi
    
    if [ -f "$service_file" ]; then
        cp "$service_file" /etc/systemd/system/pymc-repeater.service
        
        # WORKAROUND: Add --log-level DEBUG to fix pymc_core timing bug on Pi 5
        # Issue: asyncio event loop not ready when interrupt callbacks register
        # The DEBUG flag slows down initialization enough for the event loop to start
        # TODO: File upstream issue at github.com/rightup/pyMC_core
        sed -i 's|--config /etc/pymc_repeater/config.yaml$|--config /etc/pymc_repeater/config.yaml --log-level DEBUG|' \
            /etc/systemd/system/pymc-repeater.service
        
        print_success "Installed upstream service file"
        print_info "Added --log-level DEBUG for RX timing fix"
    else
        print_error "Service file not found in pyMC_Repeater repo"
        return 1
    fi
}

# GitHub repository for UI releases (public distribution repo)
UI_REPO="dmduran12/pymc_console-dist"
UI_RELEASE_URL="https://github.com/${UI_REPO}/releases"

# Download and install dashboard from GitHub Releases
# Installs to separate directory (UI_DIR) instead of overwriting upstream Vue.js
# Configures web.web_path in config.yaml to point to our dashboard
# UPGRADE BEHAVIOR: Preserves user's UI preference (stock vs pymc_console)
install_static_frontend() {
    local version="${1:-latest}"
    local target_dir="$UI_DIR"
    local config_file="$CONFIG_DIR/config.yaml"
    local temp_file="/tmp/pymc-ui-$$.tar.gz"
    local download_url
    
    # Check current web_path BEFORE making any changes
    # This preserves user preference for stock vs pymc_console UI
    local current_web_path=""
    local is_fresh_install=true
    if [ -f "$config_file" ] && command -v yq &> /dev/null; then
        current_web_path=$(yq eval '.web.web_path // ""' "$config_file" 2>/dev/null || echo "")
        # Trim whitespace and handle "null" string
        current_web_path=$(echo "$current_web_path" | tr -d '[:space:]')
        if [ "$current_web_path" = "null" ]; then
            current_web_path=""
        fi
        # If web_path exists (even if empty), this is an upgrade, not fresh install
        if yq eval '.web | has("web_path")' "$config_file" 2>/dev/null | grep -q 'true'; then
            is_fresh_install=false
        fi
    fi
    
    # Construct download URL
    if [ "$version" = "latest" ]; then
        download_url="${UI_RELEASE_URL}/latest/download/pymc-ui-latest.tar.gz"
    else
        download_url="${UI_RELEASE_URL}/download/${version}/pymc-ui-${version}.tar.gz"
    fi
    
    print_info "Downloading dashboard ($version)..."
    
    # Download with curl (preferred - handles redirects better) or wget
    if command -v curl &> /dev/null; then
        if ! curl -fsSL -o "$temp_file" "$download_url"; then
            print_error "Failed to download dashboard from $download_url"
            rm -f "$temp_file"
            return 1
        fi
    elif command -v wget &> /dev/null; then
        # wget needs explicit redirect following for GitHub releases
        if ! wget -q --max-redirect=5 -O "$temp_file" "$download_url"; then
            print_error "Failed to download dashboard from $download_url"
            print_info "Check your internet connection or try a specific version"
            rm -f "$temp_file"
            return 1
        fi
    else
        print_error "Neither curl nor wget found - cannot download dashboard"
        return 1
    fi
    
    # Verify download (check file exists and has content)
    if [ ! -s "$temp_file" ]; then
        print_error "Downloaded file is empty - release may not exist"
        print_info "Available releases: ${UI_RELEASE_URL}"
        rm -f "$temp_file"
        return 1
    fi
    
    # Remove existing dashboard if present (clean upgrade)
    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir"
    fi
    
    # Create parent directories
    mkdir -p "$(dirname "$target_dir")"
    mkdir -p "$target_dir"
    
    # Extract to target directory
    if ! tar -xzf "$temp_file" -C "$target_dir" 2>/dev/null; then
        print_error "Failed to extract dashboard archive"
        rm -f "$temp_file"
        return 1
    fi
    
    # Clean up temp file
    rm -f "$temp_file"
    
    # Set permissions
    chown -R "$SERVICE_USER:$SERVICE_USER" "$CONSOLE_DIR" 2>/dev/null || true
    
    # Configure CherryPy web_path based on user preference
    # - Fresh install: set web_path to our dashboard
    # - Upgrade with pymc_console selected: keep pointing to our dashboard
    # - Upgrade with stock UI selected (empty web_path): preserve user's choice
    if [ -f "$config_file" ] && command -v yq &> /dev/null; then
        # Ensure web section exists
        if ! yq eval '.web' "$config_file" 2>/dev/null | grep -q -v "null"; then
            yq -i '.web = {}' "$config_file" 2>/dev/null || true
        fi
        
        if [ "$is_fresh_install" = true ]; then
            # Fresh install: default to pymc_console dashboard
            yq -i ".web.web_path = \"$target_dir\"" "$config_file" 2>/dev/null || {
                print_warning "Could not set web_path in config - manual configuration may be required"
            }
            print_success "Configured web_path: $target_dir"
        elif [ -n "$current_web_path" ]; then
            # Upgrade: user was using pymc_console, keep it that way
            # (Update path in case it moved, though it shouldn't)
            yq -i ".web.web_path = \"$target_dir\"" "$config_file" 2>/dev/null || true
            print_success "Preserved UI preference: pymc_console dashboard"
        else
            # Upgrade: user was using stock UI (web_path is empty/null)
            # Preserve their preference - don't change web_path
            print_success "Preserved UI preference: stock (RightUp) frontend"
            print_info "Switch to pymc_console via Settings → Web Frontend"
        fi
    else
        print_warning "Could not configure web_path - yq not available or config missing"
        print_info "Manually set web.web_path in $config_file to: $target_dir"
    fi
    
    local size=$(du -sh "$target_dir" 2>/dev/null | cut -f1 || echo "unknown")
    print_success "Dashboard installed ($size)"
    print_info "Upstream Vue.js preserved at: $INSTALL_DIR/repeater/web/html/"
    print_info "Dashboard will be served at http://<ip>:8000/"
    
    return 0
}

# Get available UI versions from GitHub
get_ui_versions() {
    local releases
    releases=$(curl -s "https://api.github.com/repos/${UI_REPO}/releases" 2>/dev/null | 
               grep -oP '"tag_name":\s*"\K[^"]+' | head -10)
    echo "$releases"
}

merge_config() {
    local user_config="$1"
    local example_config="$2"
    
    if [ ! -f "$user_config" ] || [ ! -f "$example_config" ]; then
        echo "    Config merge skipped (files not found)"
        return 0
    fi
    
    if ! command -v yq &> /dev/null; then
        echo "    Config merge skipped (yq not available)"
        return 0
    fi
    
    local temp_merged="${user_config}.merged"
    
    if yq eval-all '. as $item ireduce ({}; . * $item)' "$example_config" "$user_config" > "$temp_merged" 2>/dev/null; then
        if yq eval '.' "$temp_merged" > /dev/null 2>&1; then
            mv "$temp_merged" "$user_config"
            echo "    ✓ Configuration merged (user settings preserved, new options added)"
        else
            rm -f "$temp_merged"
            echo "    ⚠ Merge validation failed, keeping original"
        fi
    else
        rm -f "$temp_merged"
        echo "    ⚠ Merge failed, keeping original"
    fi
}

# ============================================================================
# Main Menu
# ============================================================================

show_main_menu() {
    local status=$(get_status_display)
    
    CHOICE=$($DIALOG --backtitle "pyMC Console Management" --title "pyMC Console" --menu "\nStatus: $status\n\nChoose an action:" 20 70 10 \
        "install" "Install pyMC Console (fresh install)" \
        "upgrade" "Upgrade existing installation" \
        "settings" "Configure radio settings" \
        "gpio" "GPIO configuration (advanced)" \
        "start" "Start services" \
        "stop" "Stop services" \
        "restart" "Restart services" \
        "logs" "View live logs" \
        "uninstall" "Uninstall pyMC Console" \
        "exit" "Exit" 3>&1 1>&2 2>&3)
    
    case $CHOICE in
        "install") do_install ;;
        "upgrade") do_upgrade ;;
        "settings") do_settings ;;
        "gpio") do_gpio ;;
        "start") do_start ;;
        "stop") do_stop ;;
        "restart") do_restart ;;
        "logs")
            clear
            echo "=== Live Logs (Press Ctrl+C to return) ==="
            echo ""
            journalctl -u "$BACKEND_SERVICE" -f
            ;;
        "uninstall") do_uninstall ;;
        "exit"|"") exit 0 ;;
    esac
}

# ============================================================================
# CLI Help
# ============================================================================

show_help() {
    echo "pyMC Console Management Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
echo "Commands:"
    echo "  install     Install pyMC Console (fresh install)"
    echo "  upgrade     Upgrade existing installation"
    echo "  settings    Configure radio settings"
    echo "  gpio        GPIO configuration (advanced)"
    echo "  start       Start pyMC Repeater service"
    echo "  stop        Stop pyMC Repeater service"
    echo "  restart     Restart pyMC Repeater service"
    echo "  uninstall   Completely remove pyMC Console"
    echo ""
    echo "Run without arguments for interactive menu."
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Handle CLI arguments
case "$1" in
    "--help"|"-h")
        show_help
        exit 0
        ;;
    "install")
        check_terminal
        setup_dialog
        do_install "$2"
        exit 0
        ;;
    "upgrade")
        check_terminal
        setup_dialog
        do_upgrade
        exit 0
        ;;
    "settings")
        check_terminal
        setup_dialog
        do_settings
        exit 0
        ;;
    "gpio")
        check_terminal
        setup_dialog
        do_gpio
        exit 0
        ;;
    "start")
        check_terminal
        setup_dialog
        do_start
        exit 0
        ;;
    "stop")
        check_terminal
        setup_dialog
        do_stop
        exit 0
        ;;
    "restart")
        check_terminal
        setup_dialog
        do_restart
        exit 0
        ;;
    "uninstall")
        check_terminal
        setup_dialog
        do_uninstall
        exit 0
        ;;
esac

# Interactive menu mode
check_terminal
setup_dialog

while true; do
    show_main_menu
done
