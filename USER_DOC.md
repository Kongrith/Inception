# User documentation

## What the stack provides

| Service   | What it does for you |
|-----------|----------------------|
| NGINX     | The only door into the stack. Serves the website over HTTPS (TLSv1.2/1.3) on port 443. |
| WordPress | The website and its administration panel (runs with php-fpm). |
| MariaDB   | The database that stores posts, pages, users and settings. |

Data is kept between restarts in `/home/<login>/data/` on the host.

## Start and stop the project

Run these commands from the root of the repository:

| Action | Command |
|--------|---------|
| Build and start everything | `make` |
| Stop (containers kept, restart later with `make start`) | `make stop` |
| Start again after `make stop` | `make start` |
| Stop and remove containers (data kept) | `make down` |
| Remove everything including the data | `make fclean` |

## Access the website and the administration panel

1. Once only, make the domain point to this machine: `make hosts`
   (adds `127.0.0.1 <login>.42.fr` to `/etc/hosts`).
2. Website: `https://<login>.42.fr`
3. Administration panel: `https://<login>.42.fr/wp-admin`

The certificate is self-signed, so the browser shows a warning the first
time: choose *Advanced → Accept the risk / Proceed*.
`http://` (port 80) is intentionally not available.

## Locate and manage credentials

| What | Where |
|------|-------|
| Admin user name (`WP_ADMIN_USER`), second user (`WP_USER`), DB user (`MYSQL_USER`) | `srcs/.env` |
| Admin and second-user passwords | `secrets/credentials.txt` |
| Database password of the WordPress user | `secrets/db_password.txt` |
| Database root password | `secrets/db_root_password.txt` |

The `secrets/` files are created automatically with random passwords on the
first `make` and are never committed to git. To read the admin password:

```sh
cat secrets/credentials.txt
```

To use your own passwords, edit those files **before the first** `make`.
Passwords are only applied when the data folders are empty; to change them
later either change them inside WordPress (*Users → Profile*) or reset
everything with `make fclean && make`.

## Check that the services are running

```sh
make ps                       # the 3 containers must be "Up" (mariadb "healthy")
make logs                     # live logs of all services (Ctrl+C to quit)
docker logs wordpress         # logs of one service
curl -kI https://<login>.42.fr   # should answer HTTP/1.1 200 OK (or 30x)
```

Check that only TLS 1.2 / 1.3 is accepted:

```sh
openssl s_client -connect <login>.42.fr:443 -tls1_2 < /dev/null   # works
openssl s_client -connect <login>.42.fr:443 -tls1_1 < /dev/null   # refused
```

Check the database from the inside:

```sh
docker exec -it mariadb mariadb -u root -p    # password = secrets/db_root_password.txt
SHOW DATABASES;  SELECT user, host FROM mysql.user;
```
