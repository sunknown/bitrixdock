# CLI Installation for Bitrix Site Manager

This project implements a command-line interface for automated Bitrix Site Manager installation, allowing you to install Bitrix without manual browser interaction.

## Files Created

### 1. `www/install_cli.php`
A command-line interface script that wraps the original `bitrixsetup.php` functionality to work in CLI mode.

### 2. `cli_install.sh`
A shell wrapper script that orchestrates the Docker container execution and provides a user-friendly command-line interface.

## Features

- Full command-line installation of Bitrix Site Manager
- Support for different editions (start, business, small_business, standard, etc.)
- Support for demo and commercial licenses
- Multiple language support (ru, en, de)
- Automatic download and unpacking
- Docker container integration

## Usage

### Direct PHP Script Usage
```bash
# List available editions
php www/install_cli.php --action=list --lang=ru

# Install with default settings (start edition, demo license, Russian language)
php www/install_cli.php --edition=start --demo --lang=ru --auto

# Install with commercial license
php www/install_cli.php --edition=start --commercial --license-key=YOUR_KEY --lang=ru
```

### Docker Wrapper Script Usage
```bash
# Install start edition with demo license (Russian is default)
./cli_install.sh --edition=start --demo

# Install business edition with demo license and Russian language
./cli_install.sh --edition=business --demo --lang=ru

# Install with commercial license
./cli_install.sh --edition=start --commercial --license-key=YOUR_KEY

# Verbose installation
./cli_install.sh --edition=start --demo --verbose
```

## Options

- `--edition=EDITION`: Specify edition (start, business, small_business, standard)
- `--lang=LANG`: Language (ru, en, de) - default: ru
- `--demo`: Use demo license (default)
- `--commercial`: Use commercial license
- `--license-key=KEY`: Commercial license key
- `--auto`: Auto-start unpacking after download
- `--verbose`: Enable verbose output
- `--help`: Show help

## Prerequisites

- Docker and Docker Compose installed
- BitrixDock environment running

## How It Works

The CLI installation works by:

1. The shell script (`cli_install.sh`) starts the Docker containers if not running
2. Executes the PHP CLI script (`install_cli.php`) inside the PHP container
3. The PHP script simulates HTTP requests to the original `bitrixsetup.php` with appropriate parameters
4. Handles the download and unpacking process automatically

## Automation

The installation can be fully automated using the `--auto` flag which will automatically proceed to unpacking after downloading the distribution file.

## License

The demo license option allows for evaluation of Bitrix products without requiring a commercial license key.