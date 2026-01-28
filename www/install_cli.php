<?php
/**
 * Command-line Interface for Bitrix Installation
 * This script provides CLI functionality to automate Bitrix installation
 */

// Define CLI mode
define('CLI_MODE', true);

// Function to check if running in CLI mode
function is_cli_mode() {
    return php_sapi_name() === 'cli';
}

// Function to output messages to console
function cli_output($message, $newline = true) {
    if ($newline) {
        echo $message . PHP_EOL;
    } else {
        echo $message;
    }
}

// Function to display help
function show_help() {
    cli_output("Usage: php install_cli.php [OPTIONS]");
    cli_output("");
    cli_output("Options:");
    cli_output("  --action=ACTION      Specify action: list, load, unpack, install");
    cli_output("  --edition=EDITION    Specify edition to install (start, business, small_business, standard)");
    cli_output("  --demo               Use demo license (default)");
    cli_output("  --commercial         Use commercial license");
    cli_output("  --license-key=KEY    Specify commercial license key");
    cli_output("  --lang=LANG          Language (ru, en, de) - default: en");
    cli_output("  --auto               Automatically start unpacking after download");
    cli_output("  --verbose            Enable verbose output");
    cli_output("  --help               Show this help message");
    cli_output("");
    cli_output("Examples:");
    cli_output("  php install_cli.php --edition=start --demo --auto");
    cli_output("  php install_cli.php --edition=business --demo --lang=ru");
    cli_output("  php install_cli.php --edition=start --commercial --license-key=XXXXX");
}

// Function to parse command line arguments
function parse_cli_args() {
    global $argv;

    $options = [
        'action' => '',
        'edition' => 'start',
        'license_type' => 'demo',  // demo or src
        'license_key' => '',
        'lang' => 'ru',
        'auto' => false,
        'verbose' => false,
        'help' => false
    ];

    foreach ($argv as $arg) {
        if (strpos($arg, '--') === 0) {
            $parts = explode('=', $arg);
            $param = substr($parts[0], 2);

            if (count($parts) > 1) {
                $value = $parts[1];
            } else {
                $value = true;
            }

            switch ($param) {
                case 'action':
                    $options['action'] = $value;
                    break;
                case 'edition':
                    $options['edition'] = $value;
                    break;
                case 'demo':
                    $options['license_type'] = 'demo';
                    break;
                case 'commercial':
                    $options['license_type'] = 'src';
                    break;
                case 'license-key':
                    $options['license_key'] = $value;
                    $options['license_type'] = 'src';
                    break;
                case 'lang':
                    $options['lang'] = $value;
                    break;
                case 'auto':
                    $options['auto'] = true;
                    break;
                case 'verbose':
                    $options['verbose'] = true;
                    break;
                case 'help':
                    $options['help'] = true;
                    break;
            }
        }
    }

    return $options;
}

// Function to get edition mapping based on language
function get_editions_by_language($lang = 'en') {
    $editions = [
        'ru' => [
            'start' => 'start',
            'business' => 'business',
            'small_business' => 'small_business',
            'standard' => 'standard',
            'bitrix24' => 'portal/bitrix24',
            'enterprise' => 'portal/bitrix24_enterprise',
            'crm' => 'portal/bitrix24_crm'
        ],
        'en' => [
            'start' => 'start',
            'business' => 'business',
            'small_business' => 'small_business',
            'standard' => 'standard',
            'bitrix24' => 'portal/en_bitrix24',
            'enterprise' => 'portal/en_bitrix24_enterprise',
            'crm' => 'portal/en_bitrix24_crm'
        ],
        'de' => [
            'start' => 'start',
            'business' => 'business',
            'small_business' => 'small_business',
            'standard' => 'standard',
            'bitrix24' => 'de/de_bitrix24',
            'enterprise' => 'de/de_bitrix24_enterprise',
            'crm' => 'de/de_bitrix24_crm'
        ]
    ];

    return isset($editions[$lang]) ? $editions[$lang] : $editions['en'];
}

// Function to simulate HTTP request to bitrixsetup.php
function simulate_request($params = [], $suppress_output = true) {
    // Save original globals
    $orig_get = $_GET;
    $orig_post = $_POST;
    $orig_request = $_REQUEST;
    $orig_server = $_SERVER;
    $orig_env = $_ENV;

    // Set up simulated request
    $_GET = $params;
    $_POST = $params;
    $_REQUEST = $params;

    // Simulate server variables
    $_SERVER['DOCUMENT_ROOT'] = dirname(__FILE__);
    $_SERVER['HTTP_HOST'] = 'localhost';
    $_SERVER['REQUEST_URI'] = '/bitrixsetup.php';
    $_SERVER['SCRIPT_NAME'] = '/bitrixsetup.php';
    $_SERVER['HTTP_USER_AGENT'] = 'BitrixSetupCLI';
    $_SERVER['REMOTE_ADDR'] = '127.0.0.1';

    // Capture output if not suppressing
    if ($suppress_output) {
        ob_start();
        include 'bitrixsetup.php';
        $output = ob_get_clean();
    } else {
        include 'bitrixsetup.php';
        $output = '';
    }

    // Restore original globals
    $_GET = $orig_get;
    $_POST = $orig_post;
    $_REQUEST = $orig_request;
    $_SERVER = $orig_server;
    $_ENV = $orig_env;

    return $output;
}

// Main function to handle CLI installation
function handle_cli_installation($options) {
    if ($options['help']) {
        show_help();
        return 0;
    }

    if ($options['verbose']) {
        cli_output("Starting Bitrix CLI installation...");
        cli_output("Edition: " . $options['edition']);
        cli_output("License Type: " . $options['license_type']);
        cli_output("Language: " . $options['lang']);
        cli_output("Auto-unpack: " . ($options['auto'] ? 'yes' : 'no'));
    }

    // Validate edition exists in the language-specific list
    $available_editions = get_editions_by_language($options['lang']);
    if (!isset($available_editions[$options['edition']])) {
        cli_output("Error: Edition '" . $options['edition'] . "' is not available for language '" . $options['lang'] . "'");
        cli_output("Available editions: " . implode(', ', array_keys($available_editions)));
        return 1;
    }

    // Set language
    $_GET['lang'] = $options['lang'];
    $_REQUEST['lang'] = $options['lang'];
    $_POST['lang'] = $options['lang'];

    // Determine action
    $action = $options['action'] ?: 'install';

    switch ($action) {
        case 'list':
            // Just list available editions
            cli_output("Available editions for language '" . $options['lang'] . "':");
            foreach ($available_editions as $key => $value) {
                cli_output("- " . $key . " (" . $value . ")");
            }
            break;

        case 'install':
        case 'load':
            // Perform installation
            cli_output("Starting download of Bitrix " . $options['edition'] . " edition...");

            // Get the actual URL for the edition
            $edition_url = $available_editions[$options['edition']];

            // Prepare parameters for the original script
            $params = [
                'action' => 'LOAD',
                'edition' => 0,  // Will need to determine the correct edition index
                'url' => $edition_url,
                'lang' => $options['lang'],
                'licence_type' => $options['license_type']
            ];

            if ($options['license_type'] === 'src' && !empty($options['license_key'])) {
                $params['LICENSE_KEY'] = $options['license_key'];
            }

            if ($options['auto']) {
                $params['action_next'] = 'UNPACK';
            }

            if ($options['verbose']) {
                cli_output("Calling bitrixsetup.php with params: " . json_encode($params));
            }

            // Call the original script to download
            $result = simulate_request($params, !$options['verbose']);

            cli_output("Download completed. Distribution file should be in the root directory.");

            // If auto-unpack is enabled, proceed to unpack
            if ($options['auto']) {
                cli_output("Auto-unpack enabled, proceeding with unpacking...");

                // Find the downloaded distribution file
                $pattern = $_SERVER['DOCUMENT_ROOT'] . '/' . basename($edition_url) . '*.tar.gz';
                $dist_files = glob($pattern);

                if (empty($dist_files)) {
                    // Try with common patterns
                    $dist_files = array_merge(
                        glob($_SERVER['DOCUMENT_ROOT'] . '/*.tar.gz'),
                        glob($_SERVER['DOCUMENT_ROOT'] . '/*.tar.gz.tmp')
                    );
                }

                if (empty($dist_files)) {
                    cli_output("Error: No distribution files found to unpack.", true);
                    return 1;
                }

                // Use the most recently created file
                $latest_file = null;
                $latest_time = 0;
                foreach ($dist_files as $file) {
                    $file_time = filemtime($file);
                    if ($file_time > $latest_time) {
                        $latest_time = $file_time;
                        $latest_file = $file;
                    }
                }

                if ($latest_file) {
                    $dist_file = basename($latest_file);
                    cli_output("Found distribution file: " . $dist_file);

                    // Prepare parameters for unpacking
                    $unpack_params = [
                        'action' => 'UNPACK',
                        'filename' => $dist_file,
                        'lang' => $options['lang'],
                        'by_step' => 'Y'
                    ];

                    if ($options['verbose']) {
                        cli_output("Unpacking with params: " . json_encode($unpack_params));
                    }

                    // Call the original script for unpacking
                    $unpack_result = simulate_request($unpack_params, !$options['verbose']);

                    cli_output("Unpacking completed.");

                    // Clean up the distribution file after unpacking
                    $current_dir = getcwd();
                    if (file_exists($current_dir . '/' . $dist_file)) {
                        unlink($current_dir . '/' . $dist_file);
                        cli_output("Cleaned up distribution file: " . $dist_file);
                    }
                } else {
                    cli_output("Error: Could not determine which distribution file to unpack.", true);
                    return 1;
                }
            }

            break;

        case 'unpack':
            cli_output("Unpacking downloaded distribution...");

            // Find the downloaded distribution file based on the edition
            $edition_url = $available_editions[$options['edition']];

            // Different editions have different file naming patterns
            $current_dir = getcwd();
            $possible_patterns = [
                $current_dir . '/' . basename($edition_url) . '*.tar.gz',
                $current_dir . '/' . basename($edition_url) . '*encode*.tar.gz',
                $current_dir . '/' . basename($edition_url) . '*source*.tar.gz',
                $current_dir . '/*.tar.gz'
            ];

            $dist_file = null;
            foreach ($possible_patterns as $pattern) {
                $dist_files = glob($pattern);
                if (!empty($dist_files)) {
                    // Use the most recently created file
                    $latest_time = 0;
                    foreach ($dist_files as $file) {
                        $file_time = filemtime($file);
                        if ($file_time > $latest_time) {
                            $latest_time = $file_time;
                            $dist_file = basename($file);
                        }
                    }
                    if ($dist_file) {
                        break;
                    }
                }
            }

            // If we still don't have a file, try to find any .tar.gz file
            if (!$dist_file) {
                $all_tar_files = glob($_SERVER['DOCUMENT_ROOT'] . '/*.tar.gz');
                if (!empty($all_tar_files)) {
                    $latest_time = 0;
                    foreach ($all_tar_files as $file) {
                        $file_time = filemtime($file);
                        if ($file_time > $latest_time) {
                            $latest_time = $file_time;
                            $dist_file = basename($file);
                        }
                    }
                }
            }

            if ($dist_file) {
                cli_output("Found distribution file: " . $dist_file);

                // Prepare parameters for unpacking
                $params = [
                    'action' => 'UNPACK',
                    'filename' => $dist_file,
                    'lang' => $options['lang'],
                    'by_step' => 'Y'
                ];

                if ($options['verbose']) {
                    cli_output("Unpacking with params: " . json_encode($params));
                }

                // Call the original script for unpacking
                $result = simulate_request($params, !$options['verbose']);

                cli_output("Unpacking completed.");

                // Clean up the distribution file after unpacking
                $current_dir = getcwd();
                if (file_exists($current_dir . '/' . $dist_file)) {
                    unlink($current_dir . '/' . $dist_file);
                    cli_output("Cleaned up distribution file: " . $dist_file);
                }
            } else {
                cli_output("Error: No distribution files found to unpack.", true);
                return 1;
            }

            break;

        default:
            cli_output("Unknown action: " . $action);
            show_help();
            return 1;
    }

    return 0;
}

// Main execution
if (is_cli_mode()) {
    $options = parse_cli_args();
    $exit_code = handle_cli_installation($options);
    exit($exit_code);
} else {
    // If accessed via web, show error
    header('Content-Type: text/plain');
    echo "This script is designed to run in CLI mode only.";
}
?>