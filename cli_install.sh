#!/bin/bash

# Command-line installation wrapper for Bitrix
# Usage: ./cli_install.sh --edition=start --lang=en

set -e # Exit on any error

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
case $EDITION in
start | business | small_business | standard) ;;
*)
    echo "Error: Invalid edition '$EDITION'. Valid options: start, business, small_business, standard"
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

# Build the PHP command arguments safely
PHP_ARGS="--edition=${EDITION} --lang=${LANG}"

if [ "$DEMO" = "true" ]; then
    PHP_ARGS="$PHP_ARGS --demo"
else
    PHP_ARGS="$PHP_ARGS --commercial"
    if [ -n "$LICENSE_KEY" ]; then
        PHP_ARGS="$PHP_ARGS --license-key=${LICENSE_KEY}"
    fi
fi

if [ "$AUTO" = "true" ]; then
    PHP_ARGS="$PHP_ARGS --auto"
fi

if [ "$VERBOSE" = "true" ]; then
    PHP_ARGS="$PHP_ARGS --verbose"
fi

echo "Starting Bitrix installation..."
echo "edition: $EDITION"
echo "Language: $LANG"
echo "License Type: $([ "$DEMO" = "true" ] && echo "Demo" || echo "Commercial")"
if [ "$COMMERCIAL" = "true" ] && [ -n "$LICENSE_KEY" ]; then
    echo "License Key: ***$(echo $LICENSE_KEY | cut -c $((${#LICENSE_KEY} - 3))-${#LICENSE_KEY})"
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

    # Check if download completed - dynamically determine the correct filename based on edition
    ARCHIVE_PATTERN="/var/www/bitrix/${EDITION}_encode.tar.gz"
    TEMP_PATTERN="/var/www/bitrix/${EDITION}_encode.tar.gz.tmp"

    # Also check for other possible patterns based on edition
    if [ "$EDITION" = "start" ]; then
        ARCHIVE_PATTERN="/var/www/bitrix/start_encode.tar.gz"
        TEMP_PATTERN="/var/www/bitrix/start_encode.tar.gz.tmp"
    elif [ "$EDITION" = "business" ]; then
        ARCHIVE_PATTERN="/var/www/bitrix/business_encode.tar.gz"
        TEMP_PATTERN="/var/www/bitrix/business_encode.tar.gz.tmp"
    elif [ "$EDITION" = "small_business" ]; then
        ARCHIVE_PATTERN="/var/www/bitrix/small_business_encode.tar.gz"
        TEMP_PATTERN="/var/www/bitrix/small_business_encode.tar.gz.tmp"
    elif [ "$EDITION" = "standard" ]; then
        ARCHIVE_PATTERN="/var/www/bitrix/standard_encode.tar.gz"
        TEMP_PATTERN="/var/www/bitrix/standard_encode.tar.gz.tmp"
    fi

    if docker exec "$CONTAINER_NAME" test -f "$ARCHIVE_PATTERN" || docker exec "$CONTAINER_NAME" test -f "$TEMP_PATTERN"; then
        echo "Download in progress or completed. Checking for completion..."

        # Wait for download to complete if it's still in progress
        timeout=1200 # 20 minutes timeout to allow for larger downloads
        count=0

        # Wait for temp file to disappear (indicating download is complete)
        while docker exec "$CONTAINER_NAME" test -f "$TEMP_PATTERN" && [ $count -lt $timeout ]; do
            echo -n "."

            # Check if the temp file is growing to see if download is progressing
            if docker exec "$CONTAINER_NAME" test -f "$TEMP_PATTERN"; then
                SIZE1=$(docker exec "$CONTAINER_NAME" stat -c%s "$TEMP_PATTERN" 2>/dev/null || echo 0)
                sleep 10
                SIZE2=$(docker exec "$CONTAINER_NAME" stat -c%s "$TEMP_PATTERN" 2>/dev/null || echo 0)

                # If temp file size is stable (not growing), consider download complete/stalled
                if [ "$SIZE1" -gt 0 ] && [ "$SIZE1" -eq "$SIZE2" ]; then
                    echo ""
                    echo "Temp file size is stable, download may be completed or stalled: ${SIZE1} bytes."

                    # Additional check: see if the final file now exists (meaning download completed)
                    if docker exec "$CONTAINER_NAME" test -f "$ARCHIVE_PATTERN"; then
                        echo "Final file detected, assuming download completed."
                        break
                    else
                        echo "Final file not yet available, download may have stalled."

                        # Check if the temp file is large enough to be the complete archive
                        # Sometimes the download completes but the file isn't renamed due to JS redirect issues in CLI
                        # Different editions may have different sizes, so we'll be more flexible
                        if [ $SIZE1 -gt 10000000 ]; then  # If larger than 10MB, likely complete for most editions
                            echo "Large temp file detected (${SIZE1} bytes), attempting to rename to final file..."

                            # Try to rename the temp file to the final name (since download likely completed but JS didn't rename)
                            if docker exec "$CONTAINER_NAME" mv "$TEMP_PATTERN" "$ARCHIVE_PATTERN" 2>/dev/null; then
                                echo "Successfully renamed temp file to final archive file (${SIZE1} bytes)."
                                break
                            else
                                echo "Could not rename temp file. Download may require web interface to complete."
                                break
                            fi
                        else
                            echo "Temp file size (${SIZE1} bytes) suggests download may not be fully completed."
                            break
                        fi
                    fi
                fi
            fi

            sleep 5
            count=$((count + 5))
        done

        # Final verification: ensure the archive file exists and has non-zero size
        if docker exec "$CONTAINER_NAME" test -f "$ARCHIVE_PATTERN" && [ "$(docker exec "$CONTAINER_NAME" stat -c%s "$ARCHIVE_PATTERN" 2>/dev/null || echo 0)" -gt 0 ]; then
            echo ""
            echo "Download completed successfully. Starting unpacking..."

            # Enhanced verification: wait for the file size to remain stable over time
            # This ensures the download is completely finished before unpacking
            PREV_SIZE=$(docker exec "$CONTAINER_NAME" stat -c%s "$ARCHIVE_PATTERN" 2>/dev/null || echo 0)
            STABLE_COUNT=0
            MAX_STABLE_CHECKS=3  # Require 3 consecutive stable readings

            while [ $STABLE_COUNT -lt $MAX_STABLE_CHECKS ]; do
                sleep 3
                CURR_SIZE=$(docker exec "$CONTAINER_NAME" stat -c%s "$ARCHIVE_PATTERN" 2>/dev/null || echo 0)

                if [ "$CURR_SIZE" -eq "$PREV_SIZE" ] && [ "$CURR_SIZE" -gt 0 ]; then
                    STABLE_COUNT=$((STABLE_COUNT + 1))
                    if [ $STABLE_COUNT -lt $MAX_STABLE_CHECKS ]; then
                        echo "File size stable at ${CURR_SIZE} bytes (${STABLE_COUNT}/${MAX_STABLE_CHECKS})..."
                    fi
                else
                    # Size changed, reset counter
                    echo "File size changed from ${PREV_SIZE} to ${CURR_SIZE} bytes, resetting stability check..."
                    STABLE_COUNT=0
                    PREV_SIZE=$CURR_SIZE
                fi
            done

            echo "Verified archive integrity - size is stable: ${CURR_SIZE} bytes"

            # Run unpack command
            if [ "$VERBOSE" = "true" ]; then
                docker exec -i "$CONTAINER_NAME" php /var/www/bitrix/install_cli.php --action=unpack --edition="$EDITION" --lang=$LANG
            else
                docker exec -i "$CONTAINER_NAME" php /var/www/bitrix/install_cli.php --action=unpack --edition="$EDITION" --lang=$LANG 2>/dev/null
            fi
        else
            echo ""
            echo "Error: Archive file was not found or is empty after download completed."
            echo "Looked for: $ARCHIVE_PATTERN"
            # List files in the directory to help with debugging
            echo "Files in /var/www/bitrix/:"
            docker exec "$CONTAINER_NAME" ls -la /var/www/bitrix/ 2>/dev/null || true
            exit 1
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
