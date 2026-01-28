#!/bin/bash

# Command-line installation wrapper for Bitrix
# Usage: ./cli_install.sh --edition=start --lang=en

set -e  # Exit on any error

# Default values
EDITION="start"
LANG="ru"
DEMO="true"
LICENSE_KEY=""
AUTO="false"
VERBOSE="false"

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --edition=EDITION    Specify edition to install (start, business, small_business, standard) [default: start]"
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
    echo "  $0 --edition=start --commercial --license-key=XXXXX"
}

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --edition=*)
            EDITION="${arg#*=}"
            shift
            ;;
        --lang=*)
            LANG="${arg#*=}"
            shift
            ;;
        --demo)
            DEMO="true"
            COMMERCIAL="false"
            shift
            ;;
        --commercial)
            COMMERCIAL="true"
            DEMO="false"
            shift
            ;;
        --license-key=*)
            LICENSE_KEY="${arg#*=}"
            COMMERCIAL="true"
            DEMO="false"
            shift
            ;;
        --auto)
            AUTO="true"
            shift
            ;;
        --verbose)
            VERBOSE="true"
            shift
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
case $EDITION in
    start|business|small_business|standard)
        ;;
    *)
        echo "Error: Invalid edition '$EDITION'. Valid options: start, business, small_business, standard"
        exit 1
        ;;
esac

# Validate language
case $LANG in
    ru|en|de)
        ;;
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
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! command -v docker compose &> /dev/null; then
    echo "Error: docker-compose or docker compose is not installed or not in PATH"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running"
    exit 1
fi

# Determine which docker-compose command to use
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker compose &> /dev/null; then
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

# Build the PHP command arguments
PHP_ARGS="--edition=$EDITION --lang=$LANG"

if [ "$DEMO" = "true" ]; then
    PHP_ARGS="$PHP_ARGS --demo"
else
    PHP_ARGS="$PHP_ARGS --commercial"
    if [ -n "$LICENSE_KEY" ]; then
        PHP_ARGS="$PHP_ARGS --license-key=$LICENSE_KEY"
    fi
fi

if [ "$AUTO" = "true" ]; then
    PHP_ARGS="$PHP_ARGS --auto"
fi

if [ "$VERBOSE" = "true" ]; then
    PHP_ARGS="$PHP_ARGS --verbose"
fi

echo "Starting Bitrix installation..."
echo "Edition: $EDITION"
echo "Language: $LANG"
echo "License Type: $([ "$DEMO" = "true" ] && echo "Demo" || echo "Commercial")"
if [ "$COMMERCIAL" = "true" ] && [ -n "$LICENSE_KEY" ]; then
    echo "License Key: ***$(echo $LICENSE_KEY | cut -c $((${#LICENSE_KEY}-3))-${#LICENSE_KEY})"
fi

# Execute the installation in the PHP container
CONTAINER_NAME=$($DOCKER_COMPOSE_CMD ps -q php)

if [ -z "$CONTAINER_NAME" ]; then
    echo "Error: Could not find PHP container"
    exit 1
fi

echo "Executing installation in PHP container..."

# Run the installation script
if [ "$VERBOSE" = "true" ]; then
    docker exec -i "$CONTAINER_NAME" php /var/www/bitrix/install_cli.php $PHP_ARGS
else
    docker exec -i "$CONTAINER_NAME" php /var/www/bitrix/install_cli.php $PHP_ARGS 2>/dev/null
fi

EXIT_CODE=$?

# Wait a moment for any background processes to complete
sleep 5

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "Initial download started successfully!"

    # Check if download completed
    if docker exec "$CONTAINER_NAME" test -f "/var/www/bitrix/start_encode.tar.gz" || docker exec "$CONTAINER_NAME" test -f "/var/www/bitrix/start_encode.tar.gz.tmp"; then
        echo "Download in progress or completed. Checking for completion..."

        # Wait for download to complete if it's still in progress
        timeout=600  # 10 minutes timeout
        count=0
        while docker exec "$CONTAINER_NAME" test -f "/var/www/bitrix/start_encode.tar.gz.tmp" && [ $count -lt $timeout ]; do
            echo -n "."
            sleep 10
            count=$((count + 10))
        done

        if docker exec "$CONTAINER_NAME" test -f "/var/www/bitrix/start_encode.tar.gz"; then
            echo ""
            echo "Download completed. Starting unpacking..."

            # Run unpack command
            if [ "$VERBOSE" = "true" ]; then
                docker exec -i "$CONTAINER_NAME" php /var/www/bitrix/install_cli.php --action=unpack --lang=$LANG
            else
                docker exec -i "$CONTAINER_NAME" php /var/www/bitrix/install_cli.php --action=unpack --lang=$LANG 2>/dev/null
            fi

            UNPACK_EXIT_CODE=$?

            if [ $UNPACK_EXIT_CODE -eq 0 ]; then
                echo ""
                echo "Installation completed successfully!"
            else
                echo ""
                echo "Unpacking failed with exit code: $UNPACK_EXIT_CODE"
                exit $UNPACK_EXIT_CODE
            fi
        else
            echo ""
            echo "Download may still be in progress. You can monitor the process in the container."
            echo "The distribution file will be located at /var/www/bitrix/ when complete."
        fi
    else
        echo "Distribution file not found. Download may still be in progress."
    fi

    echo ""
    echo "Your Bitrix installation should now be accessible at:"
    echo "  http://localhost"
    echo ""
    echo "To access the admin panel, visit:"
    echo "  http://localhost/bitrix/"
else
    echo ""
    echo "Installation failed with exit code: $EXIT_CODE"
    exit $EXIT_CODE
fi
