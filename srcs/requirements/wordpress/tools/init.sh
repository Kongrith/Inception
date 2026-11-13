#!/bin/bash
set -eu

cd /var/www/html

# Read Docker Secrets
MARIADB_PASSWORD="$(cat /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(cat /run/secrets/wp_admin_password)"
WP_USER_PASSWORD="$(cat /run/secrets/wp_user_password)"

# Validate required environment variables
: "${MARIADB_DATABASE:?MARIADB_DATABASE is required}"
: "${MARIADB_USER:?MARIADB_USER is required}"
: "${DOMAIN_NAME:?DOMAIN_NAME is required}"
: "${WP_TITLE:?WP_TITLE is required}"
: "${WP_ADMIN_USER:?WP_ADMIN_USER is required}"
: "${WP_ADMIN_EMAIL:?WP_ADMIN_EMAIL is required}"
: "${WP_USER:?WP_USER is required}"
: "${WP_USER_EMAIL:?WP_USER_EMAIL is required}"

echo "Waiting for MariaDB..."

until mariadb-admin ping \
    -h mariadb \
    -u"$MARIADB_USER" \
    -p"$MARIADB_PASSWORD" \
    --silent >/dev/null 2>&1; do
    sleep 1
done

echo "MariaDB is ready."

# Download WordPress if it does not exist
if [ ! -f /var/www/html/wp-includes/version.php ]; then
    echo "Downloading WordPress..."
    wp core download --allow-root
fi

# Create WordPress configuration
if [ ! -f /var/www/html/wp-config.php ]; then
    echo "Creating wp-config.php..."

    wp config create --allow-root \
        --dbname="$MARIADB_DATABASE" \
        --dbuser="$MARIADB_USER" \
        --dbpass="$MARIADB_PASSWORD" \
        --dbhost="mariadb:3306"
fi

# Install WordPress only if not already installed
if ! wp core is-installed --allow-root; then
    echo "Installing WordPress..."

    wp core install --allow-root \
        --url="https://$DOMAIN_NAME" \
        --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email
fi

# Create additional user if missing
if ! wp user get "$WP_USER" --allow-root >/dev/null 2>&1; then
    echo "Creating WordPress user..."

    wp user create "$WP_USER" "$WP_USER_EMAIL" \
        --user_pass="$WP_USER_PASSWORD" \
        --role=author \
        --allow-root
fi

# Set WordPress file ownership
chown -R www-data:www-data /var/www/html

echo "Starting PHP-FPM..."
exec php-fpm8.2 -F