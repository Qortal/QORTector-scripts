#!/bin/sh
# auto-fix-qortal.sh  —  POSIX /bin/sh, bullet-proofed

# ================= Colors (ANSI) =================
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# ================= Script flags =================
ARM_32_DETECTED=false
ARM_64_DETECTED=false
UPDATED_SETTINGS=false
NEW_UBUNTU_VERSION=false

# ================= Global URLs (override via env) =================
DEFAULT_SCRIPT_URL="${AUTO_FIX_SCRIPT_URL:-https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh}"
DEFAULT_SCRIPT_MIRROR="${AUTO_FIX_SCRIPT_MIRROR_URL:-https://gitea.qortal.link/crowetic/QORTector-scripts/raw/branch/main/auto-fix-qortal.sh}"

DEFAULT_SETTINGS_URL="${AUTO_FIX_SETTINGS_URL:-https://raw.githubusercontent.com/crowetic/QORTector-scripts/refs/heads/main/settings.json}"
DEFAULT_SETTINGS_MIRROR="${AUTO_FIX_SETTINGS_MIRROR_URL:-https://gitea.qortal.link/crowetic/QORTector-scripts/raw/branch/main/settings.json}"

PATCH_SETTINGS_URL="${AUTO_FIX_PATCH_URL:-https://raw.githubusercontent.com/crowetic/QORTector-scripts/refs/heads/main/settings-patch.json}"
PATCH_SETTINGS_MIRROR="${AUTO_FIX_PATCH_MIRROR_URL:-https://gitea.qortal.link/crowetic/QORTector-scripts/raw/branch/main/settings-patch.json}"


# ================= Helpers (POSIX-safe) =================
p() { # printf wrapper
	# shellcheck disable=SC2059
	printf "%b\n" "$*"
}

atomic_write() { # atomic_write TMP DEST
	tmp="$1"; dest="$2"
	# Create parent dir if missing
	mkdir -p "$(dirname "$dest")" 2>/dev/null || true
	sync || true
	mv -f -- "$tmp" "$dest"
	sync || true
}

fetch() { # fetch URL OUTFILE [MIRROR_URL]; retries & validation for .json
	url="$1"; out="$2"; mirror="${3:-}"
	tmp="$(mktemp "${out}.XXXXXX")" || exit 1

	# Try 5 attempts with small backoff
	i=1
	while [ "$i" -le 5 ]; do
		if curl -fsSL --connect-timeout 10 --max-time 60 -o "$tmp" "$url"; then
		break
		fi
		sleep 2
		i=$((i+1))
	done

	if [ ! -s "$tmp" ] && [ -n "$mirror" ]; then
		i=1
		while [ "$i" -le 5 ]; do
		if curl -fsSL --connect-timeout 10 --max-time 60 -o "$tmp" "$mirror"; then
				break
		fi
		sleep 2
		i=$((i+1))
		done
	fi

	if [ ! -s "$tmp" ]; then
		rm -f -- "$tmp"
		return 1
	fi

	case "$out" in
		*.json)
		if command -v jq >/dev/null 2>&1; then
			if ! jq empty "$tmp" >/dev/null 2>&1; then
			p "${RED}Downloaded JSON invalid for $out${NC}"
			rm -f -- "$tmp"
			return 1
			fi
		fi
		;;
	esac

	atomic_write "$tmp" "$out"
	return 0
}

is_valid_json_file() { # is_valid_json_file FILE
	[ -s "$1" ] || return 1
	command -v jq >/dev/null 2>&1 || return 1
	jq empty "$1" >/dev/null 2>&1
}

# ================== Functions (keep order) ==================

# Function to update the script initially if needed
initial_update() {
	if [ ! -f "${HOME}/auto_fix_updated" ]; then
		p "${YELLOW}Checking for the latest version of the script...${NC}"
		dl="${HOME}/auto-fix-qortal.sh.download"
		if fetch "$DEFAULT_SCRIPT_URL" "$dl" "$DEFAULT_SCRIPT_MIRROR"; then
			# quick sanity: must contain key functions
			if grep -q "initial_update()" "$dl" && grep -q "potentially_update_settings()" "$dl"; then
				chmod +x "$dl" 2>/dev/null || true
				atomic_write "$dl" "${HOME}/auto-fix-qortal.sh"
				: > "${HOME}/auto_fix_updated"
				p "${GREEN}Script updated. Restarting...${NC}"
				exec "${HOME}/auto-fix-qortal.sh"
			else
				p "${RED}Downloaded script failed sanity check; continuing with current copy.${NC}"
				rm -f -- "$dl"
			fi
		else
				p "${YELLOW}Could not fetch updated script (network/GitHub hiccup). Continuing with current copy.${NC}"
		fi
	fi
	check_internet
}

check_internet() {
	p "${CYAN}....................................................................${NC}"
	p "${CYAN}THIS SCRIPT RUNS AUTOMATICALLY. LET IT FINISH; DO NOT CLOSE IT EARLY.${NC}"
	p "${CYAN}It keeps Qortal updated and synced. Thanks.  —crowetic${NC}"
	p "${CYAN}....................................................................${NC}"
	sleep 2
	p "${YELLOW}Checking internet connection...${NC}"
	INTERNET_STATUS="UNKNOWN"
	TIMESTAMP="$(date +%s)"

	test_connectivity() { # HEAD 200 check
		URL=$1
		curl -s --head --max-time 8 "$URL" | grep -q "200 OK"
	}

	if ping -c 1 -W 1 8.8.4.4 >/dev/null 2>&1; then
		INTERNET_STATUS="UP"
		p "${GREEN}Ping successful to 8.8.4.4${NC}"
	else
		p "${YELLOW}Ping failed, falling back to Qortal domain tests...${NC}"
		if test_connectivity "https://qortal.org"; then
			INTERNET_STATUS="UP"; p "${GREEN}Internet via qortal.org${NC}"
		elif test_connectivity "https://api.qortal.org"; then
			INTERNET_STATUS="UP"; p "${GREEN}Internet via api.qortal.org${NC}"
		elif test_connectivity "https://ext-node.qortal.link"; then
			INTERNET_STATUS="UP"; p "${GREEN}Internet via ext-node.qortal.link${NC}"
		else
			INTERNET_STATUS="DOWN"
		fi
	fi

	if [ "$INTERNET_STATUS" = "UP" ]; then
		p "${BLUE}Internet UP, continuing...${NC}"
		rm -f -- "${HOME}/Desktop/check-qortal-status.sh" 2>/dev/null || true
		cd || exit 1
		fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh" "${HOME}/qortal/check-qortal-status.sh" || true
		chmod +x "${HOME}/qortal/check-qortal-status.sh" 2>/dev/null || true
		fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh" "${HOME}/start-qortal.sh" || true
		chmod +x "${HOME}/start-qortal.sh" 2>/dev/null || true
		fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh" "${HOME}/refresh-qortal.sh" || true
		chmod +x "${HOME}/refresh-qortal.sh" 2>/dev/null || true
		check_for_raspi
	else
		p "${RED}Internet is DOWN. Please fix connection and restart device.${NC}"
		sleep 30
		exit 1
	fi
}

check_for_raspi() {
	ARCH="$(uname -m)"
	if [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
		p "${WHITE}Raspberry Pi detected, checking 32/64-bit...${NC}"
		if uname -m | grep -q 'armv7l'; then
			p "${WHITE}32-bit ARM detected, using ARM32 start script${NC}"
			ARM_32_DETECTED=true
			fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-modified-memory-args.sh" "${HOME}/start-modified-memory-args.sh" || true
			fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron" "${HOME}/auto-fix-cron" || true
			crontab "${HOME}/auto-fix-cron" 2>/dev/null || true
			chmod +x "${HOME}/start-modified-memory-args.sh" 2>/dev/null || true
			mv -f -- "${HOME}/start-modified-memory-args.sh" "${HOME}/qortal/start.sh"
			check_qortal
		else
			p "${WHITE}64-bit ARM detected, proceeding...${NC}"
			ARM_64_DETECTED=true
			check_memory
		fi
	else
		p "${YELLOW}Not a Raspberry Pi, checking Ubuntu version...${NC}"
		if command -v lsb_release >/dev/null 2>&1; then
			UBUNTU_VER="$(lsb_release -rs | cut -d. -f1)"
		else
			UBUNTU_VER="$(grep -o 'VERSION_ID="[0-9]*' /etc/os-release | tr -dc '0-9')"
		fi
		if [ -n "$UBUNTU_VER" ] && [ "$UBUNTU_VER" -ge 24 ] 2>/dev/null; then
			p "${YELLOW}Ubuntu 24+ detected.${NC}"
			NEW_UBUNTU_VERSION=true
		fi
		check_memory
	fi
}

check_memory() {
	totalm="$(free -m | awk '/^Mem:/{print $2}')"
	p "${YELLOW}RAM check: ${totalm} MB — selecting start script...${NC}"

	if [ -n "$totalm" ] && [ "$totalm" -le 6000 ] 2>/dev/null; then
		p "${WHITE}< 6GB RAM — using 4GB start script${NC}"
		fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/4GB-start.sh" "${HOME}/4GB-start.sh" || true
		mv -f -- "${HOME}/4GB-start.sh" "${HOME}/qortal/start.sh"
		chmod +x "${HOME}/qortal/start.sh" 2>/dev/null || true
	elif [ -n "$totalm" ] && [ "$totalm" -ge 6001 ] 2>/dev/null && [ "$totalm" -le 16000 ] 2>/dev/null; then
		p "${WHITE}6–16GB RAM — using mid-range start script${NC}"
		fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-6001-to-16000m.sh" "${HOME}/start-6001-to-16000m.sh" || true
		mv -f -- "${HOME}/start-6001-to-16000m.sh" "${HOME}/qortal/start.sh"
		chmod +x "${HOME}/qortal/start.sh" 2>/dev/null || true
	else
		p "${WHITE}> 16GB RAM — using high-RAM start script${NC}"
		fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-high-RAM.sh" "${HOME}/start-high-RAM.sh" || true
		mv -f -- "${HOME}/start-high-RAM.sh" "${HOME}/qortal/start.sh"
		chmod +x "${HOME}/qortal/start.sh" 2>/dev/null || true
	fi

	check_qortal
}

check_qortal() {
	p "${YELLOW}Checking qortal version (local vs remote)...${NC}"

	core_running="$(curl -s --max-time 3 localhost:12391/admin/status || true)"
	if [ -z "$core_running" ]; then
		p "${CYAN}Node not responding. Checking for bootstrapping...${NC}"
		if tail -n 20 "${HOME}/qortal/qortal.log" 2>/dev/null | grep -Ei 'bootstrap|bootstrapping' >/dev/null 2>&1; then
			p "${RED}Bootstrapping detected. Updating script and exiting current cycle...${NC}"
			update_script
		fi
		p "${RED}Core not running; waiting 2 minutes in case it is starting slowly...${NC}"
		sleep 120
	fi

	LOCAL_VERSION="$(curl -s --max-time 5 localhost:12391/admin/info | grep -o '"buildVersion":"qortal-[^"]*' | sed 's/.*qortal-\([0-9.]*\).*/\1/' | tr -d '.')"
	REMOTE_VERSION="$(curl -s --max-time 10 "https://api.github.com/repos/qortal/qortal/releases/latest" | grep -o '"tag_name": "v[^"]*' | sed 's/.*v\([0-9.]*\).*/\1/' | tr -d '.')"

	if [ -n "$LOCAL_VERSION" ] && [ -n "$REMOTE_VERSION" ]; then
		if [ "$LOCAL_VERSION" -ge "$REMOTE_VERSION" ] 2>/dev/null; then
			p "${GREEN}Local >= remote; no core update needed.${NC}"
			check_for_GUI
		else
			check_hash_update_qortal
		fi
	else
		check_hash_update_qortal
	fi
}

check_hash_update_qortal() {
	p "${RED}Version check inconclusive or outdated. Doing hash check...${NC}"
	cd "${HOME}/qortal" || exit 1
	md5sum qortal.jar >/dev/null 2>&1 && md5sum qortal.jar > "local.md5"
	cd || exit 1
	p "${CYAN}Downloading latest core jar for comparison...${NC}"
	fetch "https://github.com/qortal/qortal/releases/latest/download/qortal.jar" "${HOME}/qortal.jar" || true
	md5sum "${HOME}/qortal.jar" >/dev/null 2>&1 && md5sum "${HOME}/qortal.jar" > "${HOME}/remote.md5"

	LOCAL="$(cat "${HOME}/qortal/local.md5" 2>/dev/null || true)"
	REMOTE="$(cat "${HOME}/remote.md5" 2>/dev/null || true)"

	if [ -n "$LOCAL" ] && [ -n "$REMOTE" ] && [ "$LOCAL" = "$REMOTE" ]; then
		p "${CYAN}Hash check: core up-to-date. Checking environment...${NC}"
		check_for_GUI
		return 0
	else
		p "${RED}Core outdated. Updating and preparing bootstrap...${NC}"
		cd "${HOME}/qortal" || exit 1
		killall -9 java 2>/dev/null || true
		sleep 3
		rm -rf -- db log.t* qortal.log run.log run.pid qortal.jar 2>/dev/null || true
		cp -f -- "${HOME}/qortal.jar" "${HOME}/qortal/qortal.jar" 2>/dev/null || true
		rm -f -- "${HOME}/qortal.jar" "${HOME}/remote.md5" local.md5 2>/dev/null || true
		cd || exit 1
		potentially_update_settings
		force_bootstrap
	fi
}

check_for_GUI() {
	if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ]; then
		p "${CYAN}GUI detected. Setting up GUI auto-fix...${NC}"
		if [ "$ARM_32_DETECTED" = true ] || [ "$ARM_64_DETECTED" = true ]; then
			p "${WHITE}ARM + GUI — skipping autostart GUI; using cron for reliability.${NC}"
			setup_raspi_cron
		else
			p "${YELLOW}Installing GUI cron + autostart entries...${NC}"
			fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-GUI-cron" "${HOME}/auto-fix-GUI-cron" || true
			crontab "${HOME}/auto-fix-GUI-cron" 2>/dev/null || true
			rm -f -- "${HOME}/auto-fix-GUI-cron"
			fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal-GUI.desktop" "${HOME}/auto-fix-qortal-GUI.desktop" || true
			fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.desktop" "${HOME}/start-qortal.desktop" || true
			mkdir -p "${HOME}/.config/autostart" 2>/dev/null || true
			cp -f -- "${HOME}/auto-fix-qortal-GUI.desktop" "${HOME}/.config/autostart" 2>/dev/null || true
			cp -f -- "${HOME}/start-qortal.desktop" "${HOME}/.config/autostart" 2>/dev/null || true
			rm -f -- "${HOME}/auto-fix-qortal-GUI.desktop" "${HOME}/start-qortal.desktop"
			p "${YELLOW}Auto-fix will run in a terminal ~7 minutes after login.${NC}"
			p "${CYAN}Continuing to verify node height...${NC}"
			check_height
		fi
	else
		p "${YELLOW}Headless system detected, setting cron then checking height...${NC}"
		setup_raspi_cron
	fi
}

setup_raspi_cron() {
	p "${YELLOW}Setting cron for RPi/headless...${NC}"

	mkdir -p "${HOME}/backups/cron-backups" 2>/dev/null || true
	crontab -l > "${HOME}/backups/cron-backups/crontab-backup-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

	p "${YELLOW}Checking autostart entries to avoid double-launch...${NC}"
	if find "${HOME}/.config/autostart" -maxdepth 1 -name "start-qortal*.desktop" 2>/dev/null | grep -q .; then
		p "${RED}Autostart entry found; using GUI cron every 3 days for auto-fix...${NC}"
		fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-GUI-cron" "${HOME}/auto-fix-GUI-cron" || true
		crontab "${HOME}/auto-fix-GUI-cron" 2>/dev/null || true
		rm -f -- "${HOME}/auto-fix-GUI-cron"
		check_height
		return 0
	fi

	p "${BLUE}No autostart entries. Setting full headless cron...${NC}"
	fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/refs/heads/main/auto-fix-cron" "${HOME}/auto-fix-cron" || true
	crontab "${HOME}/auto-fix-cron" 2>/dev/null || true
	rm -f -- "${HOME}/auto-fix-cron"
	check_height
}

check_height() {
	local_height="$(curl -sS --connect-timeout 5 "http://localhost:12391/blocks/height" || true)"

	if [ -f auto_fix_last_height.txt ]; then
		previous_local_height="$(cat auto_fix_last_height.txt 2>/dev/null || true)"
		if [ -n "$previous_local_height" ] && [ "$local_height" = "$previous_local_height" ]; then
			p "${RED}Height unchanged since last run; waiting ~3 minutes to re-check...${NC}"
			sleep 188
			checked_height="$(curl -s --connect-timeout 5 "http://localhost:12391/blocks/height" || true)"
			sleep 2
			if [ "$checked_height" = "$previous_local_height" ]; then
				p "${RED}Height still unchanged; final sanity in 10s...${NC}"
				sleep 10
				new_check_again="$(curl -sS --connect-timeout 5 "http://localhost:12391/blocks/height" || true)"
				p "new height = $new_check_again | prev = $previous_local_height"
				if [ "$new_check_again" = "$previous_local_height" ]; then
					p "${RED}Unchanged; forcing bootstrap...${NC}"
					force_bootstrap
					return 0
				fi
			fi
		fi
	fi

	if [ -z "$local_height" ]; then
		p "${RED}Local height empty. Is Qortal running?${NC}"
		no_local_height
	else
		printf "%s" "$local_height" > auto_fix_last_height.txt
		remote_height_checks
	fi
}

no_local_height() {
	p "${WHITE}Checking for bootstrapping/log format...${NC}"
	if [ -f "${HOME}/qortal/qortal.log" ]; then
		if tail -n 40 "${HOME}/qortal/qortal.log" 2>/dev/null | grep -Ei 'bootstrap|bootstrapping' >/dev/null 2>&1; then
			p "${RED}Bootstrapping detected. Updating script and exiting this cycle...${NC}"
			update_script
			return 0
		fi
	else
		old_log_found=false
		for log_file in "${HOME}/qortal/log.t"*; do
			if [ -f "$log_file" ]; then
				old_log_found=true
				p "${YELLOW}Old log format found. Migrating logs & config...${NC}"
				mkdir -p "${HOME}/qortal/backup/logs" 2>/dev/null || true
				mv -f -- "${HOME}/qortal/log.t"* "${HOME}/qortal/backup/logs" 2>/dev/null || true
				if [ -f "${HOME}/qortal/log4j2.properties" ]; then
					mv -f -- "${HOME}/qortal/log4j2.properties" "${HOME}/qortal/backup/logs" 2>/dev/null || true
				fi
				fetch "https://raw.githubusercontent.com/Qortal/qortal/master/log4j2.properties" "${HOME}/qortal/log4j2.properties" || true
				p "${RED}Stopping Qortal to apply new logging; sleeping 30s...${NC}"
				cd "${HOME}/qortal" || exit 1
				./stop.sh 2>/dev/null || true
				sleep 30
				cd || exit 1
				break
			fi
		done

		if [ "$old_log_found" = false ]; then
			p "No old log files found."
		fi
	fi

	p "${GREEN}Starting Qortal Core; allowing up to ~35 minutes on slow hardware...${NC}"
	potentially_update_settings
	cd "${HOME}/qortal" || exit 1
	./start.sh 2>/dev/null || true
	sleep 2100
	cd || exit 1
	p "${GREEN}Checking if Qortal started correctly...${NC}"
	local_height_check="$(curl -sS --connect-timeout 5 "http://localhost:12391/blocks/height" || true)"

	if [ -n "$local_height_check" ]; then
		p "${GREEN}Local height ${CYAN}${local_height_check}${NC}"
		p "${GREEN}Node looks good; re-checking height and continuing...${NC}"
		check_height
	else
		p "${RED}Start failed; forcing bootstrap...${NC}"
		force_bootstrap
	fi
}

remote_height_checks() {
	height_api_qortal_org="$(curl -sS --connect-timeout 10 "https://api.qortal.org/blocks/height" || true)"
	height_qortal_link="$(curl -sS --connect-timeout 10 "https://qortal.link/blocks/height" || true)"
	local_height="$(curl -sS --connect-timeout 10 "http://localhost:12391/blocks/height" || true)"

	if [ -z "$height_api_qortal_org" ] || [ -z "$height_qortal_link" ]; then
		p "${RED}Remote height checks failed. Updating script and continuing later.${NC}"
		update_script
		return 0
	fi

	# fall back to last known height or 0
	case "$local_height" in
		''|*[!0-9]*) local_height="${local_height:-0}" ;;
	esac
	case "$height_api_qortal_org" in
		''|*[!0-9]*) height_api_qortal_org=0 ;;
	esac
	case "$height_qortal_link" in
		''|*[!0-9]*) height_qortal_link=0 ;;
	esac

	# within +/- 1500
	min_api=$((local_height - 1500))
	max_api=$((local_height + 1500))
	if [ "$height_api_qortal_org" -ge "$min_api" ] 2>/dev/null && [ "$height_api_qortal_org" -le "$max_api" ] 2>/dev/null; then
		p "${YELLOW}Local (${local_height}) within 1500 of api.qortal.org (${height_api_qortal_org}).${NC}"
		p "${GREEN}api.qortal.org checks PASSED, updating script...${NC}"
		update_script
	else
		p "${RED}Outside range vs api.qortal.org. Checking qortal.link...${NC}"
		min_link=$((local_height - 1500))
		max_link=$((local_height + 1500))
		if [ "$height_qortal_link" -ge "$min_link" ] 2>/dev/null && [ "$height_qortal_link" -le "$max_link" ] 2>/dev/null; then
			p "${YELLOW}Local (${local_height}) within 1500 of qortal.link (${height_qortal_link}).${NC}"
			p "${GREEN}qortal.link checks PASSED, updating script...${NC}"
			update_script
		else
			p "${RED}Both remotes out of range; forcing bootstrap...${NC}"
			force_bootstrap
		fi
	fi
}

force_bootstrap() {
	p "${RED}ISSUES DETECTED — forcing bootstrap...${NC}"
	cd "${HOME}/qortal" || exit 1
	killall -9 java 2>/dev/null || true
	sleep 3
	rm -rf -- db log.t* qortal.log run.log run.pid *.gz 2>/dev/null || true
	sleep 5
	./start.sh 2>/dev/null || true
	cd || exit 1
	p "${GREEN}Core restarted; should bootstrap now. Updating script...${NC}"
	update_script
}

potentially_update_settings() {
	p "${GREEN}Validating and updating settings.json (numeric max-merge + forced priorities)...${NC}"

	QORTAL_DIR="${HOME}/qortal"
	SETTINGS_FILE="${QORTAL_DIR}/settings.json"
	BACKUP_DIR="${QORTAL_DIR}/qortal-backup/auto-fix-settings-backup"
	TIMESTAMP="$(date +%Y%m%d%H%M%S)"
	BACKUP_FILE="${BACKUP_DIR}/backup-settings-${TIMESTAMP}.json"
	LATEST_GOOD_LINK="${BACKUP_DIR}/latest-good.json"
	TMP_FILE="$(mktemp "${QORTAL_DIR}/.settings.json.tmp.XXXXXX")"
	REMOTE_FILE="$(mktemp "${QORTAL_DIR}/.settings.remote.tmp.XXXXXX")"

	# Single canonical remote file (default + patch)
	DEFAULT_SETTINGS_URL="${AUTO_FIX_SETTINGS_URL:-https://raw.githubusercontent.com/crowetic/QORTector-scripts/refs/heads/main/settings.json}"
	DEFAULT_SETTINGS_MIRROR="${AUTO_FIX_SETTINGS_MIRROR_URL:-https://gitea.qortal.link/crowetic/QORTector-scripts/raw/branch/main/settings.json}"

	mkdir -p "${BACKUP_DIR}" 2>/dev/null || true

	# Ensure jq (best-effort)
	if ! command -v jq >/dev/null 2>&1; then
		p "${YELLOW}jq not found. Attempting install (Debian/Ubuntu)...${NC}"
		if command -v apt-get >/dev/null 2>&1; then
		if [ "$(id -u)" -ne 0 ]; then
			sudo apt-get update -y && sudo apt-get install -y jq || true
		else
			apt-get update -y && apt-get install -y jq || true
		fi
		fi
	fi

	# Backup current (even if invalid)
	if [ -f "$SETTINGS_FILE" ]; then
		cp -f -- "$SETTINGS_FILE" "$BACKUP_FILE" 2>/dev/null || true
		if is_valid_json_file "$SETTINGS_FILE"; then
		ln -sfn "$(basename "$BACKUP_FILE")" "$LATEST_GOOD_LINK" 2>/dev/null || true
		fi
	fi

	# Fetch canonical remote
	if ! fetch "$DEFAULT_SETTINGS_URL" "$REMOTE_FILE" "$DEFAULT_SETTINGS_MIRROR"; then
		p "${RED}Failed to fetch remote settings (GitHub+Gitea). Aborting settings update safely.${NC}"
		rm -f -- "$TMP_FILE" "$REMOTE_FILE"
		return 1
	fi

	# If local invalid/missing: install remote as-is
	if ! is_valid_json_file "$SETTINGS_FILE"; then
		p "${YELLOW}settings.json missing/invalid. Installing remote settings as-is.${NC}"
		atomic_write "$REMOTE_FILE" "$SETTINGS_FILE"
		cp -f -- "$SETTINGS_FILE" "${BACKUP_DIR}/backup-settings-default-${TIMESTAMP}.json" 2>/dev/null || true
		ln -sfn "backup-settings-default-${TIMESTAMP}.json" "$LATEST_GOOD_LINK" 2>/dev/null || true
		p "${GREEN}settings.json created from remote.${NC}"
		return 0
	fi

	# Valid local + valid remote -> merge
	if command -v jq >/dev/null 2>&1; then
		jq -S --slurpfile remote "$REMOTE_FILE" '
		def merge_max($a;$b):
			if   ($a|type)=="object" and ($b|type)=="object" then
				( (($a|keys_unsorted) + ($b|keys_unsorted)) | unique ) as $ks
				| reduce $ks[] as $k
					({}; .[$k] =
						if   ($a|has($k)) and ($b|has($k)) then merge_max($a[$k]; $b[$k])
						elif ($a|has($k))                  then $a[$k]
						else                                     $b[$k]
						end)
			elif ($a|type)=="number" and ($b|type)=="number" then
				(if $a >= $b then $a else $b end)
			else
				# non-number leaves: prefer local if present; else remote
				if ($a == null) then $b else $a end
			end;

		def to_map_array(a):
			(a // [])
			| map(select(has("messageType") and has("limit")))
			| map({
					key: .messageType,
					# coerce numeric strings to numbers if possible, otherwise leave as-is
					value: ( .limit | if type=="string" then (tonumber? // .) else . end )
				})
			| from_entries;

		def merge_thread($l;$p):
			(to_map_array($l)) as $lm
			| (to_map_array($p)) as $pm
			| ( (($lm|keys_unsorted) + ($pm|keys_unsorted)) | unique ) as $keys
			| ( $keys
				| map({
					messageType: .,
					limit:
					( if   (($lm[.]|type)=="number") and (($pm[.]|type)=="number") then
							(if $lm[.] >= $pm[.] then $lm[.] else $pm[.] end)
						elif (($lm[.]|type)=="number") then $lm[.]
						else                                $pm[.]
						end )
				})
			);

		def force_from_remote($merged; $r; $keys):
			reduce ($keys[]) as $k
			($merged;
				if ($r|has($k)) then
					.[$k] = $r[$k]           # force EXACT value from remote, type preserved
				else
					.                         # if remote lacks the key, leave merged value as-is
				end);

		. as $local
		| ($remote[0] // {}) as $r

		# 1) Merge everything except the special array (numeric max-merge)
		| ( merge_max($local; ($r | del(.maxThreadsPerMessageType))) ) as $base

		# 2) Special-case array: max per messageType, union of types
		| ( $base
			| .maxThreadsPerMessageType =
				merge_thread($local.maxThreadsPerMessageType; $r.maxThreadsPerMessageType)
			) as $withThreads

		# 3) Force exact values for specific priority/latency keys from remote if present
		| force_from_remote(
			$withThreads;
			$r;
			[
				"handshakeThreadPriority",
				"dbCacheThreadPriority",
				"networkThreadPriority",
				"pruningThreadPriority",
				"synchronizerThreadPriority",
				"archivingPause"
			]
			)
		' "$SETTINGS_FILE" > "$TMP_FILE" 2>/dev/null

		if is_valid_json_file "$TMP_FILE"; then
			atomic_write "$TMP_FILE" "$SETTINGS_FILE"
			FINAL_BKP="${BACKUP_DIR}/backup-settings-postmerge-${TIMESTAMP}.json"
			cp -f -- "$SETTINGS_FILE" "$FINAL_BKP" 2>/dev/null || true
			ln -sfn "$(basename "$FINAL_BKP")" "$LATEST_GOOD_LINK" 2>/dev/null || true
			p "${GREEN}settings.json merged successfully (max-merge + forced priorities from remote).${NC}"
		else
			p "${RED}Merged settings became invalid. Keeping current settings.${NC}"
			rm -f -- "$TMP_FILE" "$REMOTE_FILE" 2>/dev/null || true
			return 1
		fi
	else
		p "${YELLOW}jq unavailable; skipping merge. (Local file left unchanged.)${NC}"
		rm -f -- "$REMOTE_FILE" 2>/dev/null || true
		return 0
	fi

	rm -f -- "$REMOTE_FILE" 2>/dev/null || true
	return 0
}

update_script() {
	p "${YELLOW}Updating script to newest version and backing up old one...${NC}"
	mkdir -p "${HOME}/qortal/new-scripts/backups" 2>/dev/null || true
	if [ -f "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" ]; then
		cp -f -- "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" "${HOME}/qortal/new-scripts/backups/auto-fix-$(date +%Y%m%d%H%M%S).sh" 2>/dev/null || true
	fi
	if [ -f "${HOME}/auto-fix-qortal.sh" ]; then
		cp -f -- "${HOME}/auto-fix-qortal.sh" "${HOME}/qortal/new-scripts/backups/original.sh" 2>/dev/null || true
	fi

	dl="${HOME}/qortal/new-scripts/auto-fix-qortal.sh.download"
	if fetch "$DEFAULT_SCRIPT_URL" "$dl" "$DEFAULT_SCRIPT_MIRROR"; then
		chmod +x "$dl" 2>/dev/null || true
		atomic_write "$dl" "${HOME}/qortal/new-scripts/auto-fix-qortal.sh"
		cp -f -- "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" "${HOME}/auto-fix-qortal.sh" 2>/dev/null || true
		chmod +x "${HOME}/auto-fix-qortal.sh" 2>/dev/null || true
		rm -f -- "${HOME}/auto_fix_updated"
	else
		p "${RED}Self-update fetch failed. Keeping current script. (Will try again next run.)${NC}"
	fi

	p "${YELLOW}Checking for any settings changes required...${NC}"
	sleep 1
	potentially_update_settings

	rm -f -- "${HOME}/qortal.jar" "${HOME}/run.pid" "${HOME}/run.log" "${HOME}/remote.md5" "${HOME}/qortal/local.md5" 2>/dev/null || true
	rm -f -- "${HOME}"/backups/backup-settings* 2>/dev/null || true
	p "${YELLOW}Auto-fix script run complete.${NC}"
	sleep 2
	return 0
}

# ================= Entry =================
initial_update
