#!/usr/bin/env bash

# Ensure script is run with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo" 
   exit 1
fi

# Get the current user (not root)
CURRENT_USER=$(logname)
DEFAULT_VAULT_PATH="/Users/$CURRENT_USER/Documents/Obsidian/Calendar"

# Prompt for Obsidian vault path
echo "Enter the full path to your Obsidian vault for calendar events."
echo "Press ENTER to use the default path: $DEFAULT_VAULT_PATH"
read -p "Vault Path: " OBSIDIAN_PATH

# Use default path if no input is provided
if [ -z "$OBSIDIAN_PATH" ]; then
    OBSIDIAN_PATH="$DEFAULT_VAULT_PATH"
fi

# Ensure the vault path exists
mkdir -p "$OBSIDIAN_PATH"

# Determine which profile file to use
if [ -f "/Users/$CURRENT_USER/.bash_profile" ]; then
    PROFILE_FILE="/Users/$CURRENT_USER/.bash_profile"
elif [ -f "/Users/$CURRENT_USER/.zprofile" ]; then
    PROFILE_FILE="/Users/$CURRENT_USER/.zprofile"
else
    # If no profile exists, create .bash_profile
    PROFILE_FILE="/Users/$CURRENT_USER/.bash_profile"
    touch "$PROFILE_FILE"
fi

# Remove any existing OBSIDIAN_PATH export
sed -i '' '/export OBSIDIAN_PATH=/d' "$PROFILE_FILE"

# Add OBSIDIAN_PATH to the profile
echo "export OBSIDIAN_PATH=\"$OBSIDIAN_PATH\"" >> "$PROFILE_FILE"

# Change ownership of the profile file
chown "$CURRENT_USER":staff "$PROFILE_FILE"

# Create spool directory symlink in user's home directory
USER_SAVE_DIR="/Users/$CURRENT_USER/CalendarToMD"

# Remove existing symlink or directory if it exists
if [ -L "$USER_SAVE_DIR" ] || [ -d "$USER_SAVE_DIR" ]; then
    rm -rf "$USER_SAVE_DIR"
fi

# Create symbolic link to the spool directory
ln -s "/private/var/spool/calendar-to-md" "$USER_SAVE_DIR"

# Ensure correct ownership and permissions
chown "$CURRENT_USER":staff "$USER_SAVE_DIR"

# Install Homebrew if not already installed
if ! sudo -u "$CURRENT_USER" command -v brew &> /dev/null; then
    echo "Installing Homebrew for user $CURRENT_USER..."
    sudo -u "$CURRENT_USER" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for the current user
    sudo -u "$CURRENT_USER" sh -c 'echo '"'"'eval "$(/opt/homebrew/bin/brew shellenv)"'"'" >> /Users/'"$CURRENT_USER"'/.zprofile'
    sudo -u "$CURRENT_USER" eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Install pandoc and poppler using the current user's Homebrew
sudo -u "$CURRENT_USER" brew install pandoc poppler

# Create directories for virtual printer
mkdir -p /private/etc/cups/virtual
mkdir -p /private/var/spool/calendar-to-md

# Set appropriate permissions
# Give full access to the current user
chmod 775 /private/var/spool/calendar-to-md
chown "$CURRENT_USER":_lp /private/var/spool/calendar-to-md

# Create virtual printer PPD file
cat << 'EOF' > /private/etc/cups/ppd/calendar-to-md.ppd
*PPD-Adobe: "4.3"
*FormatVersion: "4.3"
*FileVersion: "1.0"
*LanguageVersion: English
*LanguageEncoding: ISOLatin1
*PCFileName: "CALENDAR-TO-MD.PPD"
*Manufacturer: "Virtual"
*Product: "(Calendar to Markdown Printer)"
*ModelName: "Calendar to Markdown"
*ShortNickName: "Calendar MD Printer"
*NickName: "Calendar to Markdown Virtual Printer"
*PSVersion: "(3010.000) 0"
*LanguageLevel: "3"
*ColorDevice: False
*DefaultColorSpace: Gray
*FileSystem: False
*Throughput: "1"
*LandscapeOrientation: Plus90
EOF

# Create the advanced processing script
cat << 'EOF' > /usr/local/bin/calendar-to-md-processor.sh
#!/usr/bin/env bash

# Load Obsidian vault path from profile
if [ -f ~/.bash_profile ]; then
    source ~/.bash_profile
elif [ -f ~/.zprofile ]; then
    source ~/.zprofile
fi

# Fallback if OBSIDIAN_PATH is not set
if [ -z "$OBSIDIAN_PATH" ]; then
    OBSIDIAN_PATH="$HOME/Documents/Obsidian/Calendar"
fi

# Ensure the vault path exists
mkdir -p "$OBSIDIAN_PATH"

SPOOL_DIR="/private/var/spool/calendar-to-md"
TEMP_DIR="/tmp/calendar-processing"

# Ensure we're running as the current user
if [[ $EUID -eq 0 ]]; then
    echo "Do not run this script as root"
    exit 1
fi

# Create necessary directories
mkdir -p "$TEMP_DIR"

# Advanced PDF processing function
process_pdf() {
    local input_pdf="$1"
    local basename=$(basename "$input_pdf" .pdf)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local temp_txt="$TEMP_DIR/${basename}_${timestamp}.txt"
    local final_md="$OBSIDIAN_PATH/${timestamp}_calendar_event.md"

    # Multi-stage PDF conversion
    # 1. Extract text preserving layout
    pdftotext -layout "$input_pdf" "$temp_txt"

    # 2. Convert to markdown with pandoc
    pandoc "$temp_txt" \
        --from=plain \
        --to=markdown \
        --standalone \
        --wrap=none \
        -o "$final_md"

    # 3. Enhance markdown with YAML frontmatter
    {
        echo "---"
        echo "type: calendar-event"
        echo "source: Outlook Calendar"
        echo "imported: $(date +%Y-%m-%d %H:%M:%S)"
        echo "original-filename: $(basename "$input_pdf")"
        echo "---"
        echo
        cat "$final_md"
    } > "${final_md}.tmp" && mv "${final_md}.tmp" "$final_md"

    # Optional: extract creation date from PDF metadata
    pdf_date=$(pdftitle "$input_pdf" 2>/dev/null)
    if [ ! -z "$pdf_date" ]; then
        sed -i '' "1a\\
event-date: $pdf_date" "$final_md"
    fi

    # Cleanup
    rm "$temp_txt" "$input_pdf"
}

# Process new PDF files in the spool directory
process_spool() {
    # Find PDF files older than 1 second to ensure complete transfer
    find "$SPOOL_DIR" -name "*.pdf" -mtime +1s | while read -r pdf_file; do
        process_pdf "$pdf_file"
    done
}

# Run processing and exit
process_spool
EOF

# Make processing script executable
chmod 755 /usr/local/bin/calendar-to-md-processor.sh

# Create launch agent for the current user
cat << EOF > /Users/$CURRENT_USER/Library/LaunchAgents/com.user.calendar-to-md-processor.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.calendar-to-md-processor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/calendar-to-md-processor.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/$CURRENT_USER/Library/Logs/calendar-to-md-processor.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/$CURRENT_USER/Library/Logs/calendar-to-md-processor-error.log</string>
</dict>
</plist>
EOF

# Set correct permissions for the launch agent
chown "$CURRENT_USER":staff /Users/$CURRENT_USER/Library/LaunchAgents/com.user.calendar-to-md-processor.plist

# Add virtual printer to CUPS
lpadmin -p CalendarToMD \
    -E \
    -v file:/private/var/spool/calendar-to-md/ \
    -P /private/etc/cups/ppd/calendar-to-md.ppd \
    -o printer-is-shared=false

# Restart CUPS to apply changes
killall -HUP cupsd

echo "Calendar to Markdown printer installation complete!"
echo "Obsidian vault path set to: $OBSIDIAN_PATH"
echo "CalendarToMD symlink created at: $USER_SAVE_DIR"
echo ""
echo "To use:"
echo "1. In Outlook, type Ctrl+P to print"
echo "2. Select 'CalendarToMD' printer"
echo "3. Save to the CalendarToMD folder in your home directory"
echo "Markdown files will appear in your Obsidian vault within 30 seconds"
echo ""
echo "Logs can be found at:"
echo "- ~/Library/Logs/calendar-to-md-processor.log"
echo "- ~/Library/Logs/calendar-to-md-processor-error.log"