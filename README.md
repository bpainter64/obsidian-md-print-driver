# Obsidian MD Print Driver

This script sets up a virtual printer that converts calendar event PDFs to Markdown files and saves them in an Obsidian vault. The script is designed to work with macOS and integrates with CUPS (Common UNIX Printing System).

## Dependencies

- macOS
- Homebrew
- Pandoc
- Poppler

## Installation

1. **Clone the repository:**
    ```sh
    git clone <repository-url>
    cd obsidian-md-print-driver
    ```

2. **Run the installation script with sudo:**
    ```sh
    sudo ./obsidianMD_printer.sh
    ```

3. **Follow the prompts:**
    - Enter the full path to your Obsidian vault for calendar events or press ENTER to use the default path.

## How It Works

1. **Setup:**
    - The script installs Homebrew if not already installed.
    - It installs Pandoc and Poppler using Homebrew.
    - It creates necessary directories and sets appropriate permissions.
    - It creates a virtual printer PPD file and adds the virtual printer to CUPS.
    - It creates a processing script (`calendar-to-md-processor.sh`) that converts PDFs to Markdown.
    - It sets up a launch agent to run the processing script every 30 seconds.

2. **Usage:**
    - In Outlook, type Ctrl+P to print.
    - Select "CalendarToMD" printer.
    - Save to the `CalendarToMD` folder in your home directory.
    - Markdown files will appear in your Obsidian vault within 30 seconds.

## Logs

- Standard output log: `~/Library/Logs/calendar-to-md-processor.log`
- Error log: `~/Library/Logs/calendar-to-md-processor-error.log`

## Uninstallation

To uninstall the virtual printer and remove the setup, you can manually delete the following files and directories:

- `/usr/local/bin/calendar-to-md-processor.sh`
- `/Users/$CURRENT_USER/Library/LaunchAgents/com.user.calendar-to-md-processor.plist`
- `/private/etc/cups/ppd/calendar-to-md.ppd`
- `/private/var/spool/calendar-to-md`
- The symbolic link `~/CalendarToMD`

## License

This project is licensed under the MIT License.