#!/bin/bash

# Command-line installation wrapper for Bitrix using direct download
# Usage: ./cli_install_updated.sh --edition=start --lang=en

set -e # Exit on any error

# Default values
EDITION="start"
LANG="ru"
DEMO="true"
LICENSE_KEY=""
AUTO="true"
VERBOSE="true"

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --edition=EDITION    Specify edition to install (start, business, small_business, standard, bitrix24_shop, bitrix24, bitrix24_enterprise) [default: start]"
    echo "  --lang=LANG          Language (ru, en, de) [default: ru]"
    echo "  --demo               Use demo license (default)"
    echo "  --commercial         Use commercial license"
    echo "  --license-key=KEY    Specify commercial license key (requires --commercial)"
    echo "  --auto               Automatically start unpacking after download"
    echo "  --verbose            Enable verbose output"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --edition=start --demo"
    echo "  $0 --edition=business --demo --lang=ru"
    echo "  $0 --edition=bitrix24 --demo --lang=ru"
    echo "  $0 --edition=start --commercial --license-key=XXXXX"
}

# Parse command line arguments
for arg in "$@"; do
    case $arg in
    --edition=*)
        EDITION="${arg#*=}"
        ;;
    --lang=*)
        LANG="${arg#*=}"
        ;;
    --demo)
        DEMO="true"
        COMMERCIAL="false"
        ;;
    --commercial)
        COMMERCIAL="true"
        DEMO="false"
        ;;
    --license-key=*)
        LICENSE_KEY="${arg#*=}"
        COMMERCIAL="true"
        DEMO="false"
        ;;
    --auto)
        AUTO="true"
        ;;
    --verbose)
        VERBOSE="true"
        ;;
    --help)
        show_help
        exit 0
        ;;
    *)
        echo "Unknown option: $arg"
        show_help
        exit 1
        ;;
    esac
done

# Validate edition
# Validate edition
case $EDITION in
start | business | small_business | standard | bitrix24_shop | bitrix24 | bitrix24_enterprise) ;;
*)
    echo "Error: Invalid edition '$EDITION'. Valid options: start, business, small_business, standard, bitrix24_shop, bitrix24, bitrix24_enterprise" 
    exit 1
    ;;
esac

# Validate language
case $LANG in
ru | en | de) ;;
*)
    echo "Error: Invalid language '$LANG'. Valid options: ru, en, de"
    exit 1
    ;;
esac

# Check if license key is provided when using commercial license
if [ "$COMMERCIAL" = "true" ] && [ -z "$LICENSE_KEY" ]; then
    echo "Error: --license-key is required when using --commercial"
    exit 1
fi

# Check if Docker is available
if ! command -v docker &>/dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    exit 1
fi

if ! command -v docker-compose &>/dev/null && ! command -v docker compose &>/dev/null; then
    echo "Error: docker-compose or docker compose is not installed or not in PATH"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &>/dev/null; then
    echo "Error: Docker daemon is not running"
    exit 1
fi

# Determine which docker-compose command to use
if command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker compose &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "Error: Neither docker-compose nor docker compose is available"
    exit 1
fi

# Check if services are running
if [ "$($DOCKER_COMPOSE_CMD ps -q 2>/dev/null | wc -l)" -eq 0 ]; then
    echo "Starting Docker services..."
    $DOCKER_COMPOSE_CMD up -d

    # Wait for services to be ready
    echo "Waiting for services to be ready..."
    sleep 10
fi

echo "Starting Bitrix installation..."
echo "edition: $EDITION"
echo "Language: $LANG"
echo "License Type: $([ "$DEMO" = "true" ] && echo "Demo" || echo "Commercial")"
if [ "$COMMERCIAL" = "true" ] && [ -n "$LICENSE_KEY" ]; then
    echo "License Key: ***$(echo $LICENSE_KEY | cut -c $((${#LICENSE_KEY} - 3))-${#LICENSE_KEY})"
fi

# Determine the correct domain based on language
if [ "$LANG" = "ru" ]; then
    BASE_URL="https://www.1c-bitrix.ru"
else
    BASE_URL="https://www.bitrixsoft.com"
fi

# Determine download path based on license type
if [ "$COMMERCIAL" = "true" ] && [ -n "$LICENSE_KEY" ]; then
    DOWNLOAD_PATH="private/download/"
else
    DOWNLOAD_PATH="download/"
fi

# Determine file suffix based on edition and license type
if [ "$COMMERCIAL" = "true" ] && [ -n "$LICENSE_KEY" ]; then
    SUFFIX="_source.tar.gz"
else
    # For standard editions, use encode version
    if [ "$EDITION" = "small_business" ]; then
        SUFFIX="_encode_php5.tar.gz"
    else
        SUFFIX="_encode.tar.gz"
    fi
fi

# For Bitrix24 editions, use different URL pattern
if [[ "$EDITION" == *"bitrix24"* ]]; then
    # Map edition names to their specific paths
    case "$EDITION" in
        "bitrix24_shop")
            EDITION_PATH="portal/bitrix24_shop"
            ;;
        "bitrix24")
            EDITION_PATH="portal/bitrix24"
            ;;
        "bitrix24_enterprise")
            EDITION_PATH="portal/bitrix24_enterprise"
            ;;
        *)
            EDITION_PATH="$EDITION"
            ;;
    esac

    DOWNLOAD_URL="$BASE_URL/$DOWNLOAD_PATH$EDITION_PATH$SUFFIX"
else
    DOWNLOAD_URL="$BASE_URL/$DOWNLOAD_PATH$EDITION$SUFFIX"
fi

if [ "$COMMERCIAL" = "true" ] && [ -n "$LICENSE_KEY" ]; then
    DOWNLOAD_URL="$DOWNLOAD_URL?lp=$(echo -n $LICENSE_KEY | md5sum | cut -d' ' -f1)"
fi

echo "Downloading from: $DOWNLOAD_URL"

# Get container name
CONTAINER_NAME=$($DOCKER_COMPOSE_CMD ps -q php)

if [ -z "$CONTAINER_NAME" ]; then
    echo "Error: Could not find PHP container"
    exit 1
fi

echo "Executing download in PHP container..."

# Determine output file path
OUTPUT_FILE="/var/www/bitrix/${EDITION}${SUFFIX}"

# Try to download using curl first, then wget if curl fails
if docker exec "$CONTAINER_NAME" sh -c 'which curl || command -v curl' >/dev/null 2>&1; then
    echo "Using curl for download..."
    if [ "$VERBOSE" = "true" ]; then
        docker exec "$CONTAINER_NAME" sh -c "curl -L -o '$OUTPUT_FILE' '$DOWNLOAD_URL' --progress-bar"
    else
        docker exec "$CONTAINER_NAME" sh -c "curl -L -o '$OUTPUT_FILE' '$DOWNLOAD_URL' --silent"
    fi
elif docker exec "$CONTAINER_NAME" sh -c 'which wget || command -v wget' >/dev/null 2>&1; then
    echo "Using wget for download..."
    if [ "$VERBOSE" = "true" ]; then
        docker exec "$CONTAINER_NAME" sh -c "wget -O '$OUTPUT_FILE' '$DOWNLOAD_URL' --progress=bar"
    else
        docker exec "$CONTAINER_NAME" sh -c "wget -O '$OUTPUT_FILE' '$DOWNLOAD_URL' --quiet"
    fi
else
    echo "Error: Neither curl nor wget is available in the container"
    echo "Checking what's available..."
    docker exec "$CONTAINER_NAME" sh -c 'which -a curl wget'
    exit 1
fi

# Verify the download
if docker exec "$CONTAINER_NAME" test -f "$OUTPUT_FILE" && [ "$(docker exec "$CONTAINER_NAME" stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo 0)" -gt 0 ]; then
    echo "Download completed successfully!"

    # If license key was provided, create the license key file
    if [ "$COMMERCIAL" = "true" ] && [ -n "$LICENSE_KEY" ]; then
        echo "<? \$LICENSE_KEY = \""$LICENSE_KEY"\"; ?>" | docker exec -i "$CONTAINER_NAME" tee /var/www/bitrix/bitrix/license_key.php >/dev/null
        echo "License key file created."
    fi

# Optionally start unpacking
    if [ "$AUTO" = "true" ]; then
        echo "Starting unpacking with tar..."

        # Extract the archive directly to /var/www/bitrix using tar
        if [ "$VERBOSE" = "true" ]; then
            docker exec "$CONTAINER_NAME" sh -c "tar -xzf '$OUTPUT_FILE' -C /var/www/bitrix --strip-components=1 && ls -la /var/www/bitrix"
        else
            docker exec "$CONTAINER_NAME" sh -c "tar -xzf '$OUTPUT_FILE' -C /var/www/bitrix --strip-components=1"
        fi

        # Remove the downloaded archive after successful extraction
        docker exec "$CONTAINER_NAME" rm -f "$OUTPUT_FILE"

        echo ""
        echo "Extraction completed successfully!"
        echo "Files have been extracted to /var/www/bitrix directory."
        echo "Installation completed successfully!"
    else
        echo "Download completed. You can now extract the archive manually."
        echo "Inside container, run: tar -xzf $OUTPUT_FILE -C /var/www/bitrix --strip-components=1"
    fi
else
    echo "Error: Download failed or file is empty"
    echo "File location: $OUTPUT_FILE"
    docker exec "$CONTAINER_NAME" ls -la /var/www/bitrix/ 2>/dev/null || true
    exit 1
fi

echo ""
echo "Your Bitrix installation should now be accessible at:"
echo "  http://localhost"
echo ""
echo "To access the admin panel, visit:"
echo "  http://localhost/bitrix/"
