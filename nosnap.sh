#!/bin/bash

# set -e

LOG_FILE="nosnap.log"
exec 2> >(tee -a "$LOG_FILE" >&2) # Redirect stderr to log file

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be executed as root (use sudo)."
   exit 1
fi

# Validate if snap is installed
if ! command -v snap >/dev/null 2>&1; then
   echo "Snap is not installed on this system. Exiting." | tee -a "$LOG_FILE"
   exit 0
fi

echo "--- Starting Snap purge ---"

# 2. Uninstall installed snaps with informative dependency errors
echo "Removing installed snaps..." | tee -a "$LOG_FILE"
MAX_ATTEMPTS=5
ATTEMPT=1

while [ "$(snap list 2>/dev/null | wc -l)" -gt 0 ] && [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    SNAP_LIST=$(snap list 2>/dev/null | awk 'NR>1 {print $1}')
    
    if [ -z "$SNAP_LIST" ] || [[ "$SNAP_LIST" == "No" ]]; then break; fi

    for s in $SNAP_LIST; do
        # Attempt removal and capture specific stderr
        ERR_MSG=$(snap remove --purge "$s" 2>&1)
        if [ $? -ne 0 ]; then
            if echo "$ERR_MSG" | grep -q "depend"; then
                echo "Still unable to remove package $s, it is a dependency of another snap." | tee -a "$LOG_FILE"
            else
                echo "Error removing $s: $ERR_MSG" >> "$LOG_FILE"
            fi
        else
            echo "Successfully removed $s" | tee -a "$LOG_FILE"
        fi
    done
    ((ATTEMPT++))
done

# Final check if snaps are still present
if [ "$(snap list 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "Warning: Some snaps could not be removed after $MAX_ATTEMPTS attempts. Check $LOG_FILE" | tee -a "$LOG_FILE"
fi

# Remove the core and the daemon
echo "Removing snapd and tools..." | tee -a "$LOG_FILE"
apt purge -y snapd gnome-software-plugin-snap

# Cleanup of residual directories
echo "Cleaning directories..." | tee -a "$LOG_FILE"
rm -rf /var/lib/snapd
rm -rf /var/cache/snapd
rm -rf /root/snap
rm -rf /home/*/snap

# BLACKLIST: Prevent automatic reinstallation
echo "Creating preference rule to block snapd..." | tee -a "$LOG_FILE"
cat <<EOF > /etc/apt/preferences.d/nosnap.pref
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

# NEW: Flatpak and Flathub installation
echo "--- Starting Flatpak setup ---" | tee -a "$LOG_FILE"

echo "Installing flatpak..." | tee -a "$LOG_FILE"
apt update >> "$LOG_FILE" 2>&1
apt install -y flatpak gnome-software-plugin-flatpak >> "$LOG_FILE" 2>&1

echo "Adding Flathub repository..." | tee -a "$LOG_FILE"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >> "$LOG_FILE" 2>&1

echo "--- Process completed. Ubuntu is Snap-free and Flatpak-installed, please do a machine reboot. ---" | tee -a "$LOG_FILE"

echo "--- Log saved at $LOG_FILE ---" | tee -a "$LOG_FILE"
