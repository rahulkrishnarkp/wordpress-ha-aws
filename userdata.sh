#!/bin/bash
#
# LEMP bootstrap — HA WordPress (ASG + EFS, private subnets, NAT + ALB)
#
# Goal: Open ALB DNS → WordPress native setup wizard (wp-admin/install.php)
#
# What this does:
#   1.  Waits for NAT Gateway reachability
#   2.  Installs Nginx + PHP 8.1 + MySQL client + amazon-efs-utils
#   3.  Mounts EFS at /var/www/html (persistent shared web root)
#   4.  First-boot lock: only ONE instance downloads WP + writes wp-config.php
#   5.  Fetches DB credentials from Secrets Manager
#   6.  Writes wp-config.php pointing at RDS (NO wp-cli install — lets you do it)
#   7.  Configures Nginx with /health endpoint for ALB health checks
#   8.  Starts Nginx — browser hitting ALB DNS gets WordPress setup wizard


et -euo pipefail

# Terraform variables
REGION="${region}"
SECRET_ARN="${secret_arn}"
DB_HOST="${db_host}"
DB_NAME="${db_name}"
EFS_ID="${efs_id}"

WEB_ROOT="/var/www/html"
LOGFILE="/var/log/userdata.log"
LOCK_FILE="$WEB_ROOT/.bootstrap-lock"

exec > >(tee -a "$LOGFILE") 2>&1

echo "=================================================="
echo "USERDATA START $(date)"
echo "=================================================="


# 1. Wait for Internet/NAT

echo "[1/7] Waiting for internet connectivity..."

for i in $(seq 1 30); do
  if curl -sf --max-time 5 https://aws.amazon.com >/dev/null; then
    echo "Internet reachable"
    break
  fi

  echo "Retrying internet check ($i/30)..."
  sleep 10
done


# 2. Install packages

echo "[2/7] Installing packages..."

yum update -y || true

amazon-linux-extras enable nginx1 php8.1 -y

yum clean metadata

yum install -y \
  nginx \
  php \
  php-fpm \
  php-mysqlnd \
  php-json \
  php-gd \
  php-mbstring \
  php-xml \
  php-intl \
  php-zip \
  mariadb \
  amazon-efs-utils \
  jq \
  unzip \
  curl


# Configure PHP-FPM for nginx

echo "Configuring php-fpm..."

sed -i 's/^user = apache/user = nginx/' /etc/php-fpm.d/www.conf
sed -i 's/^group = apache/group = nginx/' /etc/php-fpm.d/www.conf

sed -i 's#^listen.owner = nobody#listen.owner = nginx#' /etc/php-fpm.d/www.conf
sed -i 's#^listen.group = nobody#listen.group = nginx#' /etc/php-fpm.d/www.conf

mkdir -p /run/php-fpm

systemctl enable php-fpm
systemctl start php-fpm

echo "Waiting for php-fpm socket..."

for i in $(seq 1 15); do
  if [ -S /run/php-fpm/www.sock ]; then
    echo "php-fpm socket ready"
    break
  fi
  sleep 2
done


# 3. Mount EFS

echo "[3/7] Mounting EFS..."

mkdir -p "$WEB_ROOT"

if ! grep -q "$EFS_ID" /etc/fstab; then
  echo "$EFS_ID:/ $WEB_ROOT efs _netdev,tls,iam 0 0" >> /etc/fstab
fi

for i in $(seq 1 15); do
  if mount -a -t efs && mountpoint -q "$WEB_ROOT"; then
    echo "EFS mounted successfully"
    break
  fi

  echo "Retrying EFS mount ($i/15)..."
  sleep 10
done

if ! mountpoint -q "$WEB_ROOT"; then
  echo "ERROR: Failed to mount EFS"
  exit 1
fi


# 4. Bootstrap Lock

echo "[4/7] Checking bootstrap lock..."

FIRST_BOOT=false

(
  flock -n 200 || exit 0

  if [ ! -f "$LOCK_FILE" ]; then
    echo "$(hostname)" > "$LOCK_FILE"
    touch /tmp/.is_primary
  fi

) 200>"$WEB_ROOT/.bootstrap.flock"

if [ -f /tmp/.is_primary ]; then
  FIRST_BOOT=true
  echo "PRIMARY instance selected"
else
  echo "SECONDARY instance selected"
fi


# 5. Fetch DB credentials from Secrets Manager

echo "[5/7] Fetching DB credentials..."

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text)

DB_USER=$(echo "$SECRET_JSON" | jq -r '.username')
DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password')

echo "DB_HOST=$DB_HOST"
echo "DB_NAME=$DB_NAME"
echo "DB_USER=$DB_USER"


# 6. Install WordPress

echo "[6/7] Installing WordPress..."

if [ "$FIRST_BOOT" = true ]; then

  cd /tmp

  rm -rf /tmp/wordpress /tmp/latest.tar.gz

  echo "Downloading WordPress..."

  curl -sO https://wordpress.org/latest.tar.gz

  tar -xzf latest.tar.gz

  if [ ! -f "$WEB_ROOT/wp-login.php" ]; then
    cp -r wordpress/. "$WEB_ROOT/"
    echo "WordPress copied to EFS"
  else
    echo "WordPress already exists"
  fi

 
  # Generate wp-config.php
 
  if [ ! -f "$WEB_ROOT/wp-config.php" ]; then

    echo "Generating wp-config.php..."

    SALTS=$(curl -sf https://api.wordpress.org/secret-key/1.1/salt/ || true)

cat > "$WEB_ROOT/wp-config.php" <<EOF
<?php

define( 'DB_NAME', '$${DB_NAME}' );
define( 'DB_USER', '$${DB_USER}' );
define( 'DB_PASSWORD', '$${DB_PASS}' );
define( 'DB_HOST', '$${DB_HOST}' );

define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );

$${SALTS}

\$table_prefix = 'wp_';

define( 'WP_DEBUG', false );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
EOF

    echo "wp-config.php created"

  else
    echo "wp-config.php already exists"
  fi

  chown -R nginx:nginx "$WEB_ROOT"

  find "$WEB_ROOT" -type d -exec chmod 755 {} \;
  find "$WEB_ROOT" -type f -exec chmod 644 {} \;

  echo "PRIMARY bootstrap complete"

else

  echo "Waiting for WordPress files from PRIMARY..."

  for i in $(seq 1 30); do

    if [ -f "$WEB_ROOT/wp-config.php" ] && \
       [ -f "$WEB_ROOT/wp-login.php" ]; then

      echo "WordPress files available"
      break
    fi

    echo "Waiting ($i/30)..."
    sleep 10
  done

  chown -R nginx:nginx "$WEB_ROOT"
fi


# 7. Configure Nginx

echo "[7/7] Configuring Nginx..."

rm -f /etc/nginx/conf.d/default.conf

cat > /etc/nginx/conf.d/wordpress.conf <<'NGINXCONF'
server {
    listen 80 default_server;
    server_name _;

    root /var/www/html;
    index index.php index.html;

    client_max_body_size 64M;

    location = /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        try_files $uri =404;

        include fastcgi_params;

        fastcgi_pass unix:/run/php-fpm/www.sock;

        fastcgi_index index.php;

        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;

        fastcgi_read_timeout 300;
    }

    location ~* /\.(ht|git|env) {
        deny all;
    }
}
NGINXCONF

systemctl enable nginx

nginx -t

systemctl restart nginx

echo "=================================================="
echo "USERDATA COMPLETE $(date)"
echo "Open ALB DNS to finish WordPress setup"
echo "=================================================="