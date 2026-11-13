ENV_FILE	= srcs/.env
include $(ENV_FILE)
export

DATA_DIR	= /home/$(LOGIN)/data
COMPOSE		= docker compose -f srcs/docker-compose.yml

all: up

check:
	@test -f $(ENV_FILE) || (echo "Error: $(ENV_FILE) not found" && exit 1)
	@test -n "$(LOGIN)" || (echo "Error: LOGIN is not set in $(ENV_FILE)" && exit 1)
	@test -f secrets/db_password.txt || (echo "Error: secrets/db_password.txt not found" && exit 1)
	@test -f secrets/db_root_password.txt || (echo "Error: secrets/db_root_password.txt not found" && exit 1)

dirs: check
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

up: dirs
	$(COMPOSE) up -d --build

build: check
	$(COMPOSE) build

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop
 
start:
	$(COMPOSE) start

restart: down up

ps:
	$(COMPOSE) ps

clean:
	$(COMPOSE) down --rmi all

fclean: clean
	$(COMPOSE) down --rmi all -v
	sudo rm -rf $(DATA_DIR)

re: fclean all

.PHONY: all clean fclean re