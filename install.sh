#!/bin/bash

# Installation script for win11sddm theme

# Variables
THEME_NAME="win11sddm"
THEMES_DIR="/usr/share/sddm/themes"
INSTALL_DIR="$THEMES_DIR/$THEME_NAME"
SDDM_CONF="/etc/sddm.conf"
SDDM_CONF_DIR="/etc/sddm.conf.d"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires root privileges to install the theme."
        echo "Please enter your password to continue..."

        # Re-execute the script with sudo
        exec sudo "$0" "$@"

        # If exec fails, exit with error
        echo "Failed to elevate privileges. Please run with sudo manually."
        exit 1
    fi
}

# Function to set theme in SDDM config
set_sddm_theme() {
    local conf_file="$1"

    # Check if [Theme] section exists
    if grep -q "^\[Theme\]" "$conf_file"; then
        # Check if Current= line exists in [Theme] section
        if grep -A 10 "^\[Theme\]" "$conf_file" | grep -q "^Current="; then
            # Replace existing Current= line
            sed -i "/^\[Theme\]/,/^\[.*\]/ s/^Current=.*/Current=$THEME_NAME/" "$conf_file"
            echo "  ✓ Updated Current=$THEME_NAME in [Theme] section"
        else
            # Add Current= line after [Theme] section
            sed -i "/^\[Theme\]/a Current=$THEME_NAME" "$conf_file"
            echo "  ✓ Added Current=$THEME_NAME to [Theme] section"
        fi
    else
        # Add entire [Theme] section
        echo -e "\n[Theme]\nCurrent=$THEME_NAME" >> "$conf_file"
        echo "  ✓ Created [Theme] section with Current=$THEME_NAME"
    fi
}

# Call the root check function
check_root

# Now continue with the installation as root
echo "========================================="
echo "  Windows 11 SDDM Theme Installer"
echo "========================================="
echo ""

# Check if SDDM themes directory exists
if [ ! -d "$THEMES_DIR" ]; then
    echo "Error: The SDDM themes directory ($THEMES_DIR) was not found." >&2
    echo "Please make sure SDDM is installed correctly before running this script." >&2
    echo ""
    echo "You can install SDDM with:"
    echo "  - Ubuntu/Debian: sudo apt install sddm"
    echo "  - Arch Linux: sudo pacman -S sddm"
    echo "  - Fedora: sudo dnf install sddm"
    exit 1
fi

echo "Installing theme to $INSTALL_DIR..."
echo ""

# Check if theme already exists
if [ -d "$INSTALL_DIR" ]; then
    echo "Warning: Theme already exists at $INSTALL_DIR"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo "Removing existing theme..."
    rm -rf "$INSTALL_DIR"
fi

# Create theme directory
if ! mkdir -p "$INSTALL_DIR"; then
    echo "Error: Could not create theme directory. Check permissions." >&2
    exit 1
fi

# Copy theme files
echo "Copying files..."
if ! cp -r ./* "$INSTALL_DIR/"; then
    echo "Error: Failed to copy theme files." >&2
    rm -rf "$INSTALL_DIR" # Clean up on failure
    exit 1
fi

# Set proper permissions
echo "Setting permissions..."
chmod -R 755 "$INSTALL_DIR"

echo ""
echo "========================================="
echo "  Configuring SDDM Theme"
echo "========================================="
echo ""

# Backup and configure SDDM settings
SDDM_CONFIG_MODIFIED=false

# Check if main sddm.conf exists
if [ -f "$SDDM_CONF" ]; then
    echo "Found $SDDM_CONF"
    read -p "Do you want to automatically set $THEME_NAME as the current SDDM theme? (Y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "Backing up $SDDM_CONF to ${SDDM_CONF}${BACKUP_SUFFIX}"
        cp "$SDDM_CONF" "${SDDM_CONF}${BACKUP_SUFFIX}"

        echo "Setting theme in $SDDM_CONF..."
        set_sddm_theme "$SDDM_CONF"
        SDDM_CONFIG_MODIFIED=true
    fi
else
    echo "$SDDM_CONF not found. Creating it..."
    touch "$SDDM_CONF"
    echo "Setting theme in $SDDM_CONF..."
    set_sddm_theme "$SDDM_CONF"
    SDDM_CONFIG_MODIFIED=true
fi

# Check for configuration directory (modern SDDM setups)
if [ -d "$SDDM_CONF_DIR" ]; then
    # Check if there's already a theme config file
    THEME_CONF_FILE="$SDDM_CONF_DIR/theme.conf"

    if [ -f "$THEME_CONF_FILE" ]; then
        echo ""
        echo "Found $THEME_CONF_FILE"
        read -p "Do you want to update the theme in $THEME_CONF_FILE as well? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Backing up $THEME_CONF_FILE to ${THEME_CONF_FILE}${BACKUP_SUFFIX}"
            cp "$THEME_CONF_FILE" "${THEME_CONF_FILE}${BACKUP_SUFFIX}"

            echo "Setting theme in $THEME_CONF_FILE..."
            if grep -q "^Current=" "$THEME_CONF_FILE"; then
                sed -i "s/^Current=.*/Current=$THEME_NAME/" "$THEME_CONF_FILE"
                echo "  ✓ Updated Current=$THEME_NAME"
            else
                echo "Current=$THEME_NAME" >> "$THEME_CONF_FILE"
                echo "  ✓ Added Current=$THEME_NAME"
            fi
            SDDM_CONFIG_MODIFIED=true
        fi
    else
        # Create theme.conf if it doesn't exist and user wants to
        echo ""
        read -p "Create $THEME_CONF_FILE with $THEME_NAME as the theme? (Y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "Current=$THEME_NAME" > "$THEME_CONF_FILE"
            echo "  ✓ Created $THEME_CONF_FILE with Current=$THEME_NAME"
            SDDM_CONFIG_MODIFIED=true
        fi
    fi
fi

echo ""
echo "========================================="
echo "  Installation Complete!"
echo "========================================="
echo ""
echo "Theme installed successfully at: $INSTALL_DIR"
echo ""

if [ "$SDDM_CONFIG_MODIFIED" = true ]; then
    echo "✓ Theme has been set as the current SDDM theme"
    echo ""
    echo "To apply the changes:"
    echo ""
    echo "Option 1: Restart SDDM (recommended)"
    echo "  sudo systemctl restart sddm"
    echo "  ⚠️  This will log you out immediately!"
    echo ""
    echo "Option 2: Reboot your system"
    echo "  sudo reboot"
    echo ""
    echo "Option 3: Test without logging out (for next reboot only)"
    echo "  sudo systemctl restart sddm --no-block"
    echo ""
else
    echo "Theme was NOT automatically enabled."
    echo ""
    echo "To manually enable the theme:"
    echo ""
    echo "1. Edit SDDM configuration:"
    echo "   sudo nano /etc/sddm.conf"
    echo ""
    echo "2. Add or modify the [Theme] section:"
    echo "   [Theme]"
    echo "   Current=$THEME_NAME"
    echo ""
    echo "3. If using /etc/sddm.conf.d/, edit or create:"
    echo "   sudo nano /etc/sddm.conf.d/theme.conf"
    echo "   Add: Current=$THEME_NAME"
    echo ""
    echo "4. Save and restart SDDM or reboot"
fi

echo ""
echo "Additional Information:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Theme directory: $INSTALL_DIR"
echo "• Configuration backup: ${SDDM_CONF}${BACKUP_SUFFIX} (if applicable)"
echo ""
echo "Customization:"
echo "• Edit theme settings in: $INSTALL_DIR/theme.conf"
echo "• Change background in: $INSTALL_DIR/assets/backgrounds/"
echo ""
echo "Enjoy your Windows 11 theme! 🎉"

# Ask about restarting SDDM
if [ "$SDDM_CONFIG_MODIFIED" = true ]; then
    echo ""
    read -p "Do you want to restart SDDM now? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Restarting SDDM..."
        echo "⚠️  You will be logged out in a few seconds!"
        sleep 3
        systemctl restart sddm
    else
        echo "Remember to restart SDDM or reboot to see the new theme."
    fi
fi

exit 0
