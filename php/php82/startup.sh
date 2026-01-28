#!/bin/bash

# Create necessary directories and set permissions
mkdir -p /var/run/php /var/log/php
chown www-data:www-data /var/run/php /var/log/php

# Replace the default php-fpm.conf to remove PID file requirement
# Backup the original
cp /etc/php/8.2/fpm/php-fpm.conf /etc/php/8.2/fpm/php-fpm.conf.bak

# Create a new php-fpm.conf with no PID file
{
  echo "[global]"
  echo "; No PID file to avoid permission issues when running as non-root"
  echo "error_log = /var/log/php8.2-fpm.log"
  echo "log_level = notice"
  echo "daemonize = no"
  echo ""
  echo "include=/etc/php/8.2/fpm/pool.d/*.conf"
} > /etc/php/8.2/fpm/php-fpm.conf

# Start PHP-FPM
exec php-fpm8.2 --nodaemonize --fpm-config /etc/php/8.2/fpm/php-fpm.conf