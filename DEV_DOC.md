# Developer documentation

## 1. Set up the environment from scratch

### Prerequisites (inside the VM)

- Docker Engine and the Docker Compose plugin (`docker compose version`)
- `make`, `sudo`, `git`
- Your user in the `docker` group (`sudo usermod -aG docker $USER`, then log
  out and in) so `docker` works without `sudo`
- Internet access during the build (apt packages, WP-CLI, WordPress core)

### Configuration files

| File | Role | In git? |
|------|------|---------|
| `srcs/.env` | Non-secret settings: `LOGIN`, `DOMAIN_NAME`, DB name/user, WordPress title, user names and e-mails | yes |
| `secrets/db_password.txt` | Password of `MYSQL_USER` | **no** |
| `secrets/db_root_password.txt` | MariaDB root password | **no** |
| `secrets/credentials.txt` | `WP_ADMIN_PASSWORD=...` and `WP_USER_PASSWORD=...` lines | **no** |

Steps:

```sh
git clone <repo> inception && cd inception
vim srcs/.env          # set LOGIN=<you> and DOMAIN_NAME=<you>.42.fr
make setup             # creates /home/<you>/data/* and random secrets
make hosts             # 127.0.0.1 <you>.42.fr in /etc/hosts
```

`make setup` never overwrites an existing secret file, so you can write your
own passwords in `secrets/` before running it. `WP_ADMIN_USER` must not
contain "admin" (any case); the WordPress container exits with an error
otherwise.

## 2. Build and launch with the Makefile and Docker Compose

```sh
make            # = make up : setup + docker compose up -d --build
make build      # only build the images
make re         # wipe everything and rebuild from zero
```

Under the hood the Makefile runs
`docker compose -f srcs/docker-compose.yml <command>`. Compose reads
`srcs/.env` both for `${LOGIN}` in the YAML and, through `env_file`, for the
containers' environment.

Start-up sequence:

1. **mariadb** – `entrypoint.sh` runs `mariadb-install-db` if the volume is
   empty, then creates the database, the user and the root password with
   `mariadbd --bootstrap`, then `exec mariadbd`. A healthcheck
   (`mariadb-admin ping`) marks it *healthy*.
2. **wordpress** – starts when mariadb is healthy; waits until it can log in
   to the DB, then with WP-CLI: `core download`, `config create`,
   `core install` (admin), `user create` (author). Finally
   `exec php-fpm8.2 -F` listening on `0.0.0.0:9000`.
3. **nginx** – generates the self-signed certificate if missing, renders
   `inception.conf.template` with `envsubst` (only `${DOMAIN_NAME}`), checks
   the config with `nginx -t`, then `exec nginx -g "daemon off;"`.

## 3. Manage containers and volumes

```sh
make ps / make logs                 # status / follow logs
docker compose -f srcs/docker-compose.yml logs wordpress
docker exec -it wordpress sh        # shell inside a container
docker exec -it wordpress wp user list --allow-root
docker exec -it mariadb mariadb -u root -p
docker compose -f srcs/docker-compose.yml restart nginx
docker compose -f srcs/docker-compose.yml up -d --build wordpress   # rebuild one service

docker images                       # mariadb:inception, wordpress:inception, nginx:inception
docker network inspect inception
docker volume ls                    # mariadb, wordpress
docker volume inspect wordpress     # shows device=/home/<login>/data/wordpress
```

Test the crash-restart policy:

```sh
docker exec nginx kill 1    # nginx dies...
make ps                     # ...and is "Up" again a few seconds later
```

Cleaning:

| Command | Removes |
|---------|---------|
| `make down` | containers + network |
| `make clean` | + project images + named volumes (host files stay) |
| `make fclean` | + `/home/<login>/data` + all unused docker data (`docker system prune -af`) |

## 4. Where the data is stored and how it persists

| Named volume | Mounted in | Host folder |
|--------------|------------|-------------|
| `mariadb` | `mariadb:/var/lib/mysql` | `/home/<login>/data/mariadb` |
| `wordpress` | `wordpress:/var/www/html` and `nginx:/var/www/html` (read-only) | `/home/<login>/data/wordpress` |

The volumes are declared in the top-level `volumes:` section of
`docker-compose.yml` with the `local` driver and
`driver_opts: {type: none, o: bind, device: /home/${LOGIN}/data/...}`.
They are real Docker named volumes (listed by `docker volume ls`), whose
storage location is that host folder.

Persistence: `make down`, `make stop`, a reboot of the VM or a rebuild of the
images do **not** touch these folders, so posts, users and settings survive.
Because the entrypoints check what already exists, an existing database or
WordPress install is reused as is. Only `make fclean` (or deleting the
folders by hand) resets the data.
