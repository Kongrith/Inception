#!/bin/sh
set -eu  # -e: stop at the first error, -u: stop on unset variables

DATADIR=/var/lib/mysql

# check values from .env file
: "${MARIADB_USER:?MARIADB_USER is not set}"
: "${MARIADB_DATABASE:?MARIADB_DATABASE is not set}"

# check values from secrets
for secret in db_password db_root_password; do
    if [ ! -f "/run/secrets/$secret" ]; then
        echo "[init] missing secret: /run/secrets/$secret" >&2
        exit 1
    fi
done

MARIADB_USER_PASSWORD="$(cat /run/secrets/db_password)"
MARIADB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"

# create the runtime directory (socket + pid file) and fix ownership
mkdir -p /run/mysqld
chown -R mysql:mysql "$DATADIR" /run/mysqld

# create the system database (if not exist in volume)
if [ ! -d "$DATADIR/mysql" ]; then
    echo "[init] initializing system database..."
    mariadb-install-db --user=mysql --datadir="$DATADIR" --skip-test-db > /dev/null
fi

# create the application database (WordPress) and user (only once).
# --bootstrap runs the SQL without networking, then exits.
if [ ! -d "$DATADIR/$MARIADB_DATABASE" ]; then
    echo "[init] creating database '$MARIADB_DATABASE' and user '$MARIADB_USER'"
    mariadbd --user=mysql --datadir="$DATADIR" --bootstrap <<EOF
FLUSH PRIVILEGES;

DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'$(hostname)';

CREATE DATABASE IF NOT EXISTS \`${MARIADB_DATABASE}\`;

CREATE USER IF NOT EXISTS '${MARIADB_USER}'@'%'
IDENTIFIED BY '${MARIADB_USER_PASSWORD}';

GRANT ALL PRIVILEGES
ON \`${MARIADB_DATABASE}\`.*
TO '${MARIADB_USER}'@'%';

ALTER USER 'root'@'localhost'
IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';

FLUSH PRIVILEGES;
EOF
    echo "[init] done"
else
    echo "[init] database '$MARIADB_DATABASE' already exists, skipping setup"
fi

# Start the server in the foreground as PID 1
echo "[init] starting mariadbd"
exec mariadbd --user=mysql