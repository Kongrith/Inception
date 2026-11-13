*This project has been created as part of the 42 curriculum by khkomasa.*

# Inception

## Description

Inception is a system-administration project: it builds a small web
infrastructure out of Docker containers, inside a virtual machine, with
Docker Compose. Every image is built from my own Dockerfiles on top of
`debian:bookworm` (the penultimate stable Debian release); no ready-made
service image is pulled.

The stack serves a WordPress website over HTTPS at `https://khkomasa.42.fr`:

| Container   | Content                            | Listens on                            |
|-------------|------------------------------------|---------------------------------------|
| `nginx`     | NGINX, TLSv1.2 / TLSv1.3 only      | 443 (only port published to the host) |
| `wordpress` | WordPress + php-fpm 8.2 (no nginx) | 9000 (FastCGI, internal)              |
| `mariadb`   | MariaDB (no nginx)                 | 3306 (internal)                       |

Two named volumes keep the data (`mariadb_data` for the database,
`wordpress_data` for the website files), stored on the host in
`/home/khkomasa/data`. The three containers talk over a dedicated bridge
network called `inception_network`.

```
 browser ──443/TLS──> nginx ──9000/FastCGI──> wordpress ──3306──> mariadb
                        │                        │                  │
                        └──── wordpress_data ────┘            mariadb_data
```

## Instructions

Requirements: a Linux VM with Docker Engine, the Docker Compose plugin,
`make` and `sudo`.

1. Create `srcs/.env` (not in git) with the non-secret settings. The full
   list of variables and an example are in [DEV_DOC.md](DEV_DOC.md).
2. Create the four password files in `secrets/` (not in git):
   `db_password.txt`, `db_root_password.txt`, `wp_admin_password.txt`,
   `wp_user_password.txt`.
3. Point the domain to the VM:
   `echo "127.0.0.1 khkomasa.42.fr" | sudo tee -a /etc/hosts`
4. Build and start everything: `make`
   - this creates `/home/<login>/data/{mariadb,wordpress}`, builds the three
     images and starts the containers in the background.
5. Open `https://khkomasa.42.fr` (accept the self-signed certificate
   warning). The admin panel is at `https://khkomasa.42.fr/wp-admin`.

Other targets: `make build`, `make down`, `make stop`, `make start`,
`make restart`, `make ps`, `make logs`, `make clean`, `make fclean`, `make re`.
See [USER_DOC.md](USER_DOC.md) and [DEV_DOC.md](DEV_DOC.md) for details.

## Project description

### Use of Docker and sources included

```
.
├── Makefile                     # entry point: checks, build, run, clean
├── README.md / USER_DOC.md / DEV_DOC.md
├── secrets/                     # created locally, not in git
│   ├── db_password.txt          # MariaDB password of the WordPress DB user
│   ├── db_root_password.txt     # MariaDB root password
│   ├── wp_admin_password.txt    # WordPress administrator password
│   └── wp_user_password.txt     # WordPress second user password
└── srcs/
    ├── .env                     # non-secret configuration, not in git
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/   (Dockerfile, conf/50-server.cnf, tools/init.sh)
        ├── wordpress/ (Dockerfile, conf/www.conf,      tools/init.sh)
        └── nginx/     (Dockerfile, conf/nginx.conf)
```

The `Makefile` calls `docker compose`, which builds one image per service
from its Dockerfile (image name = service name, tag `inception`, never
`latest`) and starts one container per service.

### Main design choices

- **Debian bookworm** as base image: well-known packages
  (`mariadb-server`, `php8.2-fpm`, `nginx`) and it is the penultimate stable
  release required by the subject.
- **Each main process is PID 1.** The MariaDB and WordPress init scripts
  only do the one-time setup and then call `exec`, so the shell is
  *replaced* by the real service (`mariadbd`, `php-fpm8.2 -F`). NGINX is
  started directly with `nginx -g "daemon off;"`. The services run in the
  foreground, receive the signals sent by `docker stop`, and no `tail -f` /
  `sleep infinity` / `while true` trick is used.
- **Idempotent setup.** MariaDB only creates the database and its user when
  the database does not exist yet in the volume; WordPress is installed with
  WP-CLI and every step (download, config, install, second user) is skipped
  if already done, so a restart never breaks existing data.
- **Two WordPress users**: an administrator (`WP_ADMIN_USER`, whose name
  must not contain "admin") and a second user (`WP_USER`) with the *author*
  role.
- **TLS** with a self-signed certificate generated when the nginx image is
  built; `ssl_protocols TLSv1.2 TLSv1.3;` and nothing listens on port 80.
- **Restart policy** `unless-stopped`: a crashed container is restarted
  automatically, but a container stopped on purpose stays stopped.
- **Start order**: MariaDB has a healthcheck (`mariadb-admin ping`), and
  WordPress only starts once MariaDB is healthy; NGINX starts after
  WordPress.

### Virtual Machines vs Docker

A virtual machine emulates a whole computer and runs its own kernel on top
of a hypervisor: strong isolation, but it is heavy (GBs, minutes to boot).
A Docker container is just an isolated group of processes sharing the host
kernel (namespaces + cgroups): it starts in seconds, weighs MBs and is
described by a reproducible Dockerfile, but it isolates less and must use
the host's kernel. In this project both are used: the VM is the "host", and
each service lives in its own light container inside it.

### Secrets vs Environment Variables

Environment variables are easy to use but they can leak: they are visible
with `docker inspect`, inherited by every child process and often end up in
logs or in git. Docker secrets are files mounted read-only at
`/run/secrets/<name>` only in the containers that need them, and their
source files stay out of git. Here, `.env` holds only non-sensitive settings
(login, domain, database name, user names, e-mails) and every password
comes from a secret.

### Docker Network vs Host Network

With `network: host` a container shares the host's network stack: no
isolation, every port it opens is open on the host, and names cannot be
resolved between containers. A user-defined bridge network
(`inception_network`) gives the containers a private network with an
internal DNS (`mariadb`, `wordpress` are resolved by name) and nothing is
reachable from outside except what is explicitly published — here only
`443` on nginx.

### Docker Volumes vs Bind Mounts

A bind mount maps any host path directly into a container; it depends on
the host's directory layout and is not managed by Docker. A named volume is
a Docker object (`docker volume ls/inspect`), created and managed by Docker,
that can be shared between containers by name. The subject asks for the
data to end up in `/home/login/data`, so the named volumes use the `local`
driver with `driver_opts` pointing to that folder: they are still named
volumes declared in the top-level `volumes:` section, not bind mounts in the
services.

## Resources

- Docker documentation – Dockerfile best practices:
  https://docs.docker.com/build/building/best-practices/
- Docker Compose file reference: https://docs.docker.com/reference/compose-file/
- Docker secrets in Compose: https://docs.docker.com/compose/how-tos/use-secrets/
- Docker volumes: https://docs.docker.com/engine/storage/volumes/
- NGINX SSL module: https://nginx.org/en/docs/http/ngx_http_ssl_module.html
- NGINX + PHP-FPM (FastCGI): https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html
- WP-CLI commands: https://developer.wordpress.org/cli/commands/
- MariaDB `mariadb-install-db`: https://mariadb.com/kb/en/mariadb-install-db/
- About PID 1 in containers: https://docs.docker.com/engine/containers/multi-service_container/
