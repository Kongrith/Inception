# User documentation

## What the stack provides

| Service   | What it does for you |
|-----------|----------------------|
| NGINX     | The only door into the stack. Serves the website over HTTPS (TLSv1.2/1.3) on port 443. |
| WordPress | The website and its administration panel (runs with php-fpm). |
| MariaDB   | The database that stores posts, pages, users and settings. |

Data is kept between restarts in `/home/<login>/data/` on the host.

## Start and stop the project

Run these commands from the root of the repository. `srcs/.env` and the
files in `secrets/` must exist first (see "Locate and manage credentials"
below and [DEV_DOC.md](DEV_DOC.md)).

| Action | Command |
|--------|---------|
| Build and start everything | `make` |
| Stop (containers kept) | `make stop` |
| Start again after `make stop` | `make start` |
| Stop and remove containers (data kept) | `make down` |
| Remove containers and start them again | `make restart` |
| Remove containers and images (data kept) | `make clean` |
| Remove everything including the data | `make fclean` |

## Access the website and the administration panel

1. Once only, make the domain point to this machine:

   ```sh
   echo "127.0.0.1 khkomasa.42.fr" | sudo tee -a /etc/hosts
   ```

2. Website: `https://khkomasa.42.fr`
3. Administration panel: `https://khkomasa.42.fr/wp-admin`

The certificate is self-signed, so the browser shows a warning the first
time: choose *Advanced → Accept the risk / Proceed*.
`http://` (port 80) is intentionally not available.

## Locate and manage credentials

| What | Where |
|------|-------|
| Administrator name (`WP_ADMIN_USER`), second user name (`WP_USER`), database user (`MARIADB_USER`) | `srcs/.env` |
| WordPress administrator password | `secrets/wp_admin_password.txt` |
| WordPress second user password | `secrets/wp_user_password.txt` |
| Database password of `MARIADB_USER` | `secrets/db_password.txt` |
| Database root password | `secrets/db_root_password.txt` |

Each secret file contains only the password, on one line. `srcs/.env` and
`secrets/` are ignored by git: they exist only on this machine and you
create them yourself before the first `make`. To read the administrator
password:

```sh
cat secrets/wp_admin_password.txt
```

Passwords are applied only at the first start, when the data folders are
empty. To change one later:

- WordPress users: change it inside WordPress (*Users → Profile*).
- Everything at once: edit the files in `secrets/`, then `make re`
  (**this erases the website and the database**).

## Check that the services are running

```sh
make ps                          # the 3 containers must be "Up" (mariadb "healthy")
docker logs wordpress            # logs of one service (also: nginx, mariadb)
make logs                        # live logs of all services (Ctrl+C to quit)
curl -kI https://khkomasa.42.fr  # should answer HTTP/1.1 200 OK (or 30x)
```

Check that only TLS 1.2 / 1.3 is accepted:

```sh
openssl s_client -connect khkomasa.42.fr:443 -tls1_2 < /dev/null   # works
openssl s_client -connect khkomasa.42.fr:443 -tls1_1 < /dev/null   # refused
```

Check the database from the inside:

```sh
docker exec -it mariadb mariadb -u root -p    # password = secrets/db_root_password.txt
SHOW DATABASES;  SELECT user, host FROM mysql.user;
```

Check the two WordPress users:

```sh
docker exec wordpress wp user list --allow-root
```
