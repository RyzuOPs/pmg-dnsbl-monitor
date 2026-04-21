
# PMG DNSBL Monitor

**Purpose:**
This tool helps ensure that your Proxmox Mail Gateway (PMG) is effectively using DNS-based blackhole lists (DNSBL) to block spam and malicious emails. It regularly checks the health and responsiveness of all configured DNSBL providers, so you are immediately alerted if any list stops working, is misconfigured, or your server is being rate-limited or blocked by a DNSBL provider.

**Why is this important?**

**How does it work?**
The script automatically fetches all DNSBL lists configured in your PMG (from the `postscreen_dnsbl_sites` setting). It supports both formats: with or without priority weights (e.g., `zen.spamhaus.org*2` or `zen.spamhaus.org`). All configured lists are checked, so you don't need to manually update the script when you change your DNSBL configuration in PMG.

## Features
- Automatic checking of DNSBL server responses
- Logs results to a file
- Installer with cron and logrotate configuration

## Installation

1. Clone the repository:
   ```sh
   git clone https://github.com/<your-user>/pmg-dnsbl-monitor.git
   cd pmg-dnsbl-monitor
   ```
2. Make the script executable:
   ```sh
   chmod +x pmg-dnsbl-monitor.sh
   ```
3. Run the installer as root:
   ```sh
   sudo ./pmg-dnsbl-monitor.sh --install
   ```

## Usage
- Manual check:
   ```sh
   ./pmg-dnsbl-monitor.sh --run
   ```
- Installation and configuration:
   ```sh
   sudo ./pmg-dnsbl-monitor.sh --install
   ```

## Requirements
- Proxmox Mail Gateway
- Tools: `postconf`, `host`, `cron`, `logrotate`

## Author
Łukasz Ryszkeiwicz

## License
MIT
