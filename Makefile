ENV_FILE	= srcs/.env
-include $(ENV_FILE)
export

DATA_DIR	= /home/$(LOGIN)/data
COMPOSE		= docker compose -f srcs/docker-compose.yml
SECRETS		= db_password db_root_password wp_admin_password wp_user_password

all: up

# .env must exist and define LOGIN (needed by every compose command)
check-env:
	@test -f $(ENV_FILE) || { echo "Error: $(ENV_FILE) not found (see DEV_DOC.md)"; exit 1; }
	@test -n "$(LOGIN)" || { echo "Error: LOGIN is not set in $(ENV_FILE)"; exit 1; }

# every secret file used by docker-compose.yml must exist and not be empty
check: check-env
	@for s in $(SECRETS); do \
		test -s secrets/$$s.txt || { echo "Error: secrets/$$s.txt is missing or empty"; exit 1; }; \
	done

dirs: check
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

up: dirs
	$(COMPOSE) up -d --build

build: check
	$(COMPOSE) build

down: check-env
	$(COMPOSE) down

stop: check-env
	$(COMPOSE) stop

start: check-env
	$(COMPOSE) start

restart: check-env
	$(COMPOSE) down
	$(MAKE) up

ps: check-env
	$(COMPOSE) ps

logs: check-env
	$(COMPOSE) logs -f

clean: check-env
	$(COMPOSE) down --rmi all

fclean: check-env
	$(COMPOSE) down --rmi all -v
	sudo rm -rf $(DATA_DIR)

re: fclean
	$(MAKE) all

.PHONY: all check-env check dirs up build down stop start restart ps logs clean fclean re