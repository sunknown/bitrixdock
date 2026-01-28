#!/bin/sh
set -e

# Function to check prerequisites
check_prerequisites() {
    command -v docker >/dev/null 2>&1 || { echo >&2 "Docker is required but not installed. Aborting."; exit 1; }
    command -v docker compose >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 || { echo >&2 "Docker Compose is required but not installed. Aborting."; exit 1; }
    command -v git >/dev/null 2>&1 || { echo >&2 "Git is required but not installed. Aborting."; exit 1; }

    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        echo >&2 "Docker daemon is not running. Please start Docker and try again."
        exit 1
    fi
}

# Function to detect platform
detect_platform() {
    case "$(uname -s)" in
        Linux*)     PLATFORM=Linux;;
        Darwin*)    PLATFORM=macOS;;
        *)          PLATFORM="Unknown"
    esac
}

# Default installation path is current directory, can be overridden via first argument
INSTALL_PATH="${1:-.}"

echo "Validating prerequisites..."
check_prerequisites

echo "Detecting platform..."
detect_platform

mkdir -p "$INSTALL_PATH"
cd "$INSTALL_PATH"

# Normalize to absolute path after cd
INSTALL_PATH="$(pwd -P)"

echo "Installing BitrixDock to: $INSTALL_PATH"

echo "Cloning repository..."
# Clone repository directly to current directory
if [ -d ".git" ] && [ -f "docker-compose.yml" ] && [ -f ".env_template" ]; then
    echo "Directory appears to already contain a BitrixDock installation. Skipping clone."
else
    # Clean the directory if it's empty or doesn't contain BitrixDock
    if [ -n "$(ls -A "$INSTALL_PATH" 2>/dev/null)" ]; then
        echo "Warning: Directory is not empty. Please ensure it's appropriate for installation."
    fi

    # Clone repository to current directory
    TEMP_DIR=$(mktemp -d)
    git clone --depth=1 --branch no-root https://github.com/sunknown/bitrixdock.git "$TEMP_DIR"
    cp -r "$TEMP_DIR"/* "$TEMP_DIR"/.[^.]* "$INSTALL_PATH/" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
fi

echo "Creating folder structure..."
mkdir -p "$INSTALL_PATH/www"
rm -f "$INSTALL_PATH/www/bitrixsetup.php"
curl -fsSL https://www.1c-bitrix.ru/download/scripts/bitrixsetup.php -o "$INSTALL_PATH/www/bitrixsetup.php"
chmod -R 775 "$INSTALL_PATH/www"

# Set ownership only on Linux (macOS doesn't have www-data group by default)
# Use current user instead of root to avoid permission issues with containers
if [ "$PLATFORM" = "Linux" ]; then
    if id -g www-data >/dev/null 2>&1; then
        chown -R :www-data "$INSTALL_PATH/www"
        echo "Set www-data group ownership for www directory"
    else
        echo "www-data group not found, using current user for www directory"
    fi
elif [ "$PLATFORM" = "macOS" ]; then
    echo "On macOS, using current user for www directory"
    # On macOS, we don't typically have www-data group, so we just ensure correct permissions
fi

echo "Configuring environment..."
if [ ! -f "$INSTALL_PATH/.env" ]; then
    if [ -f "$INSTALL_PATH/.env_template" ]; then
        cp -f "$INSTALL_PATH/.env_template" "$INSTALL_PATH/.env"
        echo "Created .env file from template"

        # Special handling for macOS - remove /etc/localtime mount if needed
        if [ "$PLATFORM" = "macOS" ]; then
            echo "Detected macOS - updating docker-compose.yml to remove /etc/localtime mounts if present"
            sed -i.bak 's|/etc/localtime:/etc/localtime/:ro||g' "$INSTALL_PATH/docker-compose.yml" 2>/dev/null || true
            if [ $? -eq 0 ]; then
                echo "Updated docker-compose.yml for macOS compatibility"
            fi
        fi
    else
        echo "Warning: .env_template not found. Please create .env manually."
    fi
else
    echo ".env file already exists, skipping creation"
fi

echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Review and customize the .env file if needed"
echo "2. Start the services with: docker compose up -d"
echo ""
echo "To start the services now, run:"
echo "  docker compose up -d"
echo ""
echo "Access your Bitrix installation at: http://localhost"
echo ""
