# Developer documentation

## 1. Set up the environment from scratch

### Prerequisites (inside the VM)

- Docker Engine and the Docker Compose plugin (`docker compose version`)
- `make`, `sudo`, `git`
- Your user in the `docker` group (`sudo usermod -aG docker $USER`, then log
  out and in) so `docker` works without `sudo`
- Internet access: apt packages and WP-CLI are downloaded during the build,
  WordPress core at the first start of the `wordpress` container

### Configuration files

| File | Role | In git? |
|------|------|---------|
| `srcs/.env` | Non-secret settings (see below) | **no** |
| `secrets/db_password.txt` | Password of `MARIADB_USER` | **no** |
| `secrets/db_root_password.txt` | MariaDB root password | **no** |
| `secrets/wp_admin_password.txt` | Password of `WP_ADMIN_USER` | **no** |
| `secrets/wp_user_password.txt` | Password of `WP_USER` | **no** |

`.env` and `secrets/` are listed in `.gitignore`, so they must be created by
hand after cloning.

Variables expected in `srcs/.env` (the init scripts stop with an error if
one is missing):

| Variable | Used by | Meaning |
|----------|---------|---------|
| `LOGIN` | Makefile, `docker-compose.yml` | Host user; data goes to `/home/$LOGIN/data` |
| `DOMAIN_NAME` | wordpress | Site URL (`https://$DOMAIN_NAME`) |
| `MARIADB_DATABASE` | mariadb, wordpress | Name of the WordPress database |
| `MARIADB_USER` | mariadb, wordpress | Database user of WordPress |
| `WP_TITLE` | wordpress | Site title |
| `WP_ADMIN_USER` | wordpress | Administrator login — must not contain "admin" |
| `WP_ADMIN_EMAIL` | wordpress | Administrator e-mail |
| `WP_USER` | wordpress | Second user login (role *author*) |
| `WP_USER_EMAIL` | wordpress | Second user e-mail |

`srcs/.env` is not in git, so create it by hand. Example content (set
`LOGIN` to the user of the machine you run on):

```dotenv
# APP
LOGIN=khkomasa
DOMAIN_NAME=khkomasa.42.fr

# MARIADB
MARIADB_USER=wpuser
MARIADB_DATABASE=wordpress

# WORDPRESS
WP_TITLE=Inception

WP_USER=wpwriter
WP_USER_EMAIL=wpwriter@example.com
WP_ADMIN_USER=wpboss
WP_ADMIN_EMAIL=wpboss@example.com
```

Steps:

```sh
git clone <repo> inception && cd inception

vim srcs/.env          # create it with the content shown above

mkdir -p secrets
for s in db_password db_root_password wp_admin_password wp_user_password; do
    openssl rand -hex 16 > secrets/$s.txt
done

echo "127.0.0.1 khkomasa.42.fr" | sudo tee -a /etc/hosts
```

Keep the values in `.env` simple (no spaces, quotes, `#` or `$`): the file
is read by Docker Compose and also included by the Makefile.

The domain name also appears in two files that do not read `.env`:
`server_name` in `srcs/requirements/nginx/conf/nginx.conf` and the
certificate subject (`CN=`) in `srcs/requirements/nginx/Dockerfile`. Change
them together with `DOMAIN_NAME`.

## 2. Build and launch with the Makefile and Docker Compose

```sh
make            # = make up : check + create data folders + docker compose up -d --build
make build      # only build the images
make re         # wipe everything (data included) and rebuild from zero
```

Under the hood the Makefile runs
`docker compose -f srcs/docker-compose.yml <command>`. Every target first runs
`check-env` (`srcs/.env` exists and defines `LOGIN`); `make`, `make up` and
`make build` also run `check` (the four secret files exist and are not
empty). The `dirs` target creates `/home/$LOGIN/data/mariadb` and
`/home/$LOGIN/data/wordpress`. Compose reads `srcs/.env` both for `${LOGIN}`
in the YAML and, through `env_file`, for the containers' environment. The
Makefile includes `srcs/.env`, so every target needs that file.

Start-up sequence:

1. **mariadb** – `tools/init.sh` reads the two secrets, runs
   `mariadb-install-db` if the system tables are missing, then, if the
   WordPress database does not exist yet, creates it together with its user
   and sets the root password with `mariadbd --bootstrap`. Finally
   `exec mariadbd`. A healthcheck (`mariadb-admin ping`) marks the container
   *healthy*.
2. **wordpress** – starts when mariadb is healthy; `tools/init.sh` waits
   until MariaDB answers a ping, then with WP-CLI: `core download`,
   `config create`, `core install` (administrator), `user create` (author).
   Each step is skipped if already done. Finally `exec php-fpm8.2 -F`,
   listening on `0.0.0.0:9000`.
3. **nginx** – no init script: the image already contains
   `conf/nginx.conf` and a self-signed certificate generated at build time
   in `/etc/nginx/ssl`. The container runs `nginx -g "daemon off;"`.

## 3. Manage containers and volumes

```sh
make ps                             # status
make logs                           # follow all logs (Ctrl+C to quit)
docker compose -f srcs/docker-compose.yml logs wordpress     # logs of one service
docker exec -it wordpress bash      # shell inside a container
docker exec -it wordpress wp user list --allow-root
docker exec -it mariadb mariadb -u root -p
docker compose -f srcs/docker-compose.yml restart nginx
docker compose -f srcs/docker-compose.yml up -d --build wordpress   # rebuild one service

docker images                       # mariadb:inception, wordpress:inception, nginx:inception
docker network inspect inception_network
docker volume ls                    # mariadb_data, wordpress_data
docker volume inspect wordpress_data   # shows device=/home/<login>/data/wordpress
```

Test the crash-restart policy:

```sh
docker exec nginx kill 1    # nginx dies...
make ps                     # ...and is "Up" again a few seconds later
```

Cleaning:

| Command | Removes |
|---------|---------|
| `make stop` | nothing (containers are only stopped) |
| `make down` | containers + network |
| `make clean` | containers + network + project images |
| `make fclean` | all of the above + named volumes + `/home/<login>/data` (uses `sudo`) |

## 4. Where the data is stored and how it persists

| Named volume | Mounted in | Host folder |
|--------------|------------|-------------|
| `mariadb_data` | `mariadb:/var/lib/mysql` | `/home/<login>/data/mariadb` |
| `wordpress_data` | `wordpress:/var/www/html` and `nginx:/var/www/html` | `/home/<login>/data/wordpress` |

The volumes are declared in the top-level `volumes:` section of
`docker-compose.yml` with the `local` driver and
`driver_opts: {type: none, o: bind, device: /home/${LOGIN}/data/...}`.
They are real Docker named volumes (listed by `docker volume ls`), whose
storage location is that host folder.

Persistence: `make down`, `make stop`, `make clean`, a reboot of the VM or a
rebuild of the images do **not** touch these folders, so posts, users and
settings survive. Because the init scripts check what already exists, an
existing database or WordPress install is reused as is — which also means
that changing a password file or a user name in `.env` afterwards has no
effect on existing data. Only `make fclean` (or deleting the folders by
hand) resets the data.

## 5. SSL/TLS certificate (`inception.crt` / `inception.key`)

NGINX serves the site over HTTPS with a self-signed certificate. Two files
are involved, both inside the `nginx` image in `/etc/nginx/ssl/`:

| File | What it is | Used in `nginx.conf` |
|------|------------|----------------------|
| `inception.crt` | The public certificate (X.509) sent to the browser | `ssl_certificate` |
| `inception.key` | The private key (RSA 2048 bits) matching the certificate | `ssl_certificate_key` |

They are created when the image is built, by this step of
`srcs/requirements/nginx/Dockerfile`:

```sh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/inception.key \
    -out /etc/nginx/ssl/inception.crt \
    -subj "/C=TH/ST=Bangkok/L=Bangkok/O=42/CN=khkomasa.42.fr"
```

| Option | Meaning |
|--------|---------|
| `req -x509` | Produce a self-signed certificate directly (no certificate authority) |
| `-nodes` | Do not protect the key with a passphrase, so NGINX can start unattended |
| `-days 365` | The certificate is valid for one year from the build date (OpenSSL's default is only 30 days) |
| `-newkey rsa:2048` | Generate a new 2048-bit RSA key together with the certificate |
| `-keyout` | Where the private key is written; this file must stay secret |
| `-out` | Where the certificate is written; this file is public and sent to every client |
| `-subj` | Identity written in the certificate, given on the command line so the build never waits for input |

Fields of `-subj`:

| Field | Meaning | Value |
|-------|---------|-------|
| `C` | Country (2 letters) | `TH` |
| `ST` | State or province | `Bangkok` |
| `L` | Locality (city) | `Bangkok` |
| `O` | Organization | `42` |
| `CN` | Common Name: must be the domain name of the site | `khkomasa.42.fr` |

Things to know:

- The two files exist only inside the image: they are not in git, not in
  `secrets/` and not in a volume.
- Because the certificate is self-signed, browsers show a warning and
  `curl` needs `-k`. This is expected for this project.
- `nginx.conf` only allows `ssl_protocols TLSv1.2 TLSv1.3;`.
- Docker caches the build step, so a normal `make` keeps the same
  certificate. A new one is generated only when the image is rebuilt
  without cache (or after `make fclean`, which removes the images).

Inspect the certificate:

```sh
# from inside the container
docker exec nginx openssl x509 -in /etc/nginx/ssl/inception.crt -noout -subject -dates

# as seen by a client
openssl s_client -connect khkomasa.42.fr:443 < /dev/null | openssl x509 -noout -subject -dates
```

### Renewing the certificate

A self-signed certificate cannot be extended: "renewing" means issuing a new
one that replaces the old one. Check the current validity first:

```sh
docker exec nginx openssl x509 -in /etc/nginx/ssl/inception.crt -noout -dates
# notBefore = start of validity (build date), notAfter = expiry date
```

After `notAfter`, NGINX keeps running but browsers add a "certificate
expired" warning.

**Method 1 — new key and new certificate (the normal way here).** Rebuild
the image without cache, then recreate the container:

```sh
docker compose -f srcs/docker-compose.yml build --no-cache nginx
docker compose -f srcs/docker-compose.yml up -d nginx
```

`--no-cache` is required: with the cache, Docker reuses the layer and the
certificate keeps its old expiry date. Use this method too after changing
`CN` or the validity (`-days`) in the Dockerfile.

**Method 2 — keep the key, issue only a new certificate.** Replace
`-newkey rsa:2048 -keyout ...` with `-key`, inside the running container:

```sh
docker exec nginx openssl req -x509 -days 365 \
    -key /etc/nginx/ssl/inception.key \
    -out /etc/nginx/ssl/inception.crt \
    -subj "/C=TH/ST=Bangkok/L=Bangkok/O=42/CN=khkomasa.42.fr"
docker exec nginx nginx -s reload
```

This is only temporary: the files live in the container's own layer, not in
a volume, so the change is lost as soon as the container is recreated
(`make down`, `make re`, ...). Use method 1 for a lasting renewal.