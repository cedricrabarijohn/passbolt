# =============================================================================
# Passbolt — Makefile (Local + Production)
# =============================================================================
#
#  LOCAL (self-signed cert, passbolt.local)
#   make start       → Start in background
#   make start-f     → Start in foreground
#   make stop        → Stop
#   make setup       → First-time local setup
#
#  PRODUCTION (Traefik + Let's Encrypt, real domain)
#   make start-prod  → Start production in background
#   make start-prod-f→ Start production in foreground
#   make stop-prod   → Stop production
#   make setup-prod  → First-time production setup
#
#  SHARED
#   make logs[-prod] → Tail logs
#   make status[-prod] → Container status
#   make health[-prod] → Passbolt healthcheck
#   make clean[-prod]  → ⚠ Remove everything
#   make backup-prod   → Backup DB + GPG keys
#
# =============================================================================

# --- Compose shortcuts ---
COMPOSE      = docker compose
COMPOSE_DEV  = $(COMPOSE) -f docker-compose.yml
COMPOSE_PROD = $(COMPOSE) -f docker-compose.prod.yml

# --- Load local .env if exists ---
ifneq (,$(wildcard .env))
    include .env
    export
endif

ADMIN_EMAIL   ?= admin@passbolt.local
ADMIN_FIRST   ?= Tsanta
ADMIN_LAST    ?= Admin

# =============================================================================
#  LOCAL
# =============================================================================

.PHONY: start
start: _ensure-env ## Start local (detached)
	$(COMPOSE_DEV) up -d
	@echo ""
	@echo "✅ Passbolt is starting at $(APP_FULL_BASE_URL)"
	@echo "   Run 'make logs' to follow startup progress."
	@echo "   Run 'make create-admin' to create your first admin user."

.PHONY: start-f
start-f: _ensure-env ## Start local (foreground)
	$(COMPOSE_DEV) up

.PHONY: stop
stop: ## Stop local
	$(COMPOSE_DEV) down

.PHONY: restart
restart: stop start ## Restart local

.PHONY: logs
logs: ## Tail local logs
	$(COMPOSE_DEV) logs -f

.PHONY: status
status: ## Local container status
	$(COMPOSE_DEV) ps

.PHONY: create-admin
create-admin: ## Create local admin user
	$(COMPOSE_DEV) exec passbolt su -m -c \
		"/usr/share/php/passbolt/bin/cake passbolt register_user \
		-u $(ADMIN_EMAIL) \
		-f $(ADMIN_FIRST) \
		-l $(ADMIN_LAST) \
		-r admin" \
		-s /bin/sh www-data

.PHONY: health
health: ## Run local healthcheck
	$(COMPOSE_DEV) exec passbolt su -m -c \
		"/usr/share/php/passbolt/bin/cake passbolt healthcheck" \
		-s /bin/sh www-data

.PHONY: setup
setup: _ensure-env _ensure-hosts start ## Full local first-time setup
	@echo ""
	@echo "⏳ Waiting 30s for containers to initialize..."
	@sleep 30
	@$(MAKE) create-admin
	@echo ""
	@echo "🎉 Setup complete! Open $(APP_FULL_BASE_URL) in your browser."
	@echo "   (Accept the self-signed certificate warning)"

.PHONY: clean
clean: ## ⚠ Remove local containers + volumes
	@echo "⚠  This will DELETE all local Passbolt data."
	@read -p "   Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	$(COMPOSE_DEV) down -v
	@echo "🗑  All local data removed."

.PHONY: pull
pull: ## Pull latest local images
	$(COMPOSE_DEV) pull

.PHONY: update
update: pull restart ## Update local

# =============================================================================
#  PRODUCTION
# =============================================================================

.PHONY: start-prod
start-prod: _ensure-env-prod ## Start production (detached)
	$(COMPOSE_PROD) --env-file .env.prod up -d
	@echo ""
	@echo "✅ Passbolt production starting..."
	@echo "   Traefik will auto-obtain SSL certificate for your domain."
	@echo "   Run 'make logs-prod' to follow progress."

.PHONY: start-prod-f
start-prod-f: _ensure-env-prod ## Start production (foreground)
	$(COMPOSE_PROD) --env-file .env.prod up

.PHONY: stop-prod
stop-prod: ## Stop production
	$(COMPOSE_PROD) --env-file .env.prod down

.PHONY: restart-prod
restart-prod: stop-prod start-prod ## Restart production

.PHONY: logs-prod
logs-prod: ## Tail production logs
	$(COMPOSE_PROD) --env-file .env.prod logs -f

.PHONY: status-prod
status-prod: ## Production container status
	$(COMPOSE_PROD) --env-file .env.prod ps

.PHONY: create-admin-prod
create-admin-prod: _load-prod-env ## Create production admin user
	@. ./.env.prod 2>/dev/null; \
	$(COMPOSE_PROD) --env-file .env.prod exec passbolt su -m -c \
		"/usr/share/php/passbolt/bin/cake passbolt register_user \
		-u $${ADMIN_EMAIL} \
		-f $${ADMIN_FIRST} \
		-l $${ADMIN_LAST} \
		-r admin" \
		-s /bin/sh www-data

.PHONY: health-prod
health-prod: ## Run production healthcheck
	$(COMPOSE_PROD) --env-file .env.prod exec passbolt su -m -c \
		"/usr/share/php/passbolt/bin/cake passbolt healthcheck" \
		-s /bin/sh www-data

.PHONY: setup-prod
setup-prod: _ensure-env-prod _check-prod-passwords start-prod ## Full production first-time setup
	@echo ""
	@echo "⏳ Waiting 45s for containers + SSL certificate..."
	@sleep 45
	@$(MAKE) create-admin-prod
	@echo ""
	@. ./.env.prod; \
	echo "🎉 Production setup complete! Open https://$$DOMAIN in your browser."

.PHONY: clean-prod
clean-prod: ## ⚠ Remove production containers + volumes
	@echo "⚠  This will DELETE all PRODUCTION Passbolt data (passwords, GPG keys, DB, SSL certs)."
	@read -p "   Type 'DELETE' to confirm: " confirm && [ "$$confirm" = "DELETE" ] || exit 1
	$(COMPOSE_PROD) --env-file .env.prod down -v
	@echo "🗑  All production data removed."

.PHONY: pull-prod
pull-prod: ## Pull latest production images
	$(COMPOSE_PROD) --env-file .env.prod pull

.PHONY: update-prod
update-prod: pull-prod restart-prod ## Update production

# =============================================================================
#  BACKUP (production)
# =============================================================================

.PHONY: backup-prod
backup-prod: ## Backup production DB + GPG keys
	@mkdir -p backups
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	echo "📦 Backing up database..."; \
	$(COMPOSE_PROD) --env-file .env.prod exec -T db \
		sh -c 'mariadb-dump -u root -p"$$MYSQL_ROOT_PASSWORD" --all-databases' \
		> backups/db_$$TIMESTAMP.sql; \
	echo "📦 Backing up GPG keys..."; \
	docker cp passbolt-app:/etc/passbolt/gpg backups/gpg_$$TIMESTAMP; \
	echo "📦 Backing up JWT keys..."; \
	docker cp passbolt-app:/etc/passbolt/jwt backups/jwt_$$TIMESTAMP; \
	echo "✅ Backup complete → backups/*_$$TIMESTAMP"

# =============================================================================
#  VM BOOTSTRAP (run on a fresh Ubuntu VM)
# =============================================================================

.PHONY: vm-init
vm-init: ## Install Docker + firewall on a fresh Ubuntu VM
	@echo "🔧 Installing Docker..."
	sudo apt-get update
	sudo apt-get install -y ca-certificates curl gnupg
	sudo install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
	sudo chmod a+r /etc/apt/keyrings/docker.asc
	echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $$(. /etc/os-release && echo $$VERSION_CODENAME) stable" | \
		sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	sudo apt-get update
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	sudo usermod -aG docker $$USER
	@echo ""
	@echo "🔒 Configuring firewall..."
	sudo apt-get install -y ufw
	sudo ufw default deny incoming
	sudo ufw default allow outgoing
	sudo ufw allow 22/tcp
	sudo ufw allow 80/tcp
	sudo ufw allow 443/tcp
	sudo ufw --force enable
	@echo ""
	@echo "✅ VM ready! Log out and back in (for docker group), then:"
	@echo "   1. cp .env.prod.example .env.prod"
	@echo "   2. Edit .env.prod with your domain, passwords, SMTP"
	@echo "   3. make setup-prod"

# =============================================================================
#  GENERATE PASSWORDS
# =============================================================================

.PHONY: gen-passwords
gen-passwords: ## Generate strong random passwords for .env.prod
	@echo "🔐 Generated passwords (copy into .env.prod):"
	@echo ""
	@echo "MYSQL_ROOT_PASSWORD=$$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"
	@echo "MYSQL_PASSWORD=$$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"
	@echo ""

# =============================================================================
#  INTERNAL HELPERS
# =============================================================================

.PHONY: _ensure-env
_ensure-env:
	@if [ ! -f .env ]; then \
		echo "📋 Creating .env from .env.example..."; \
		cp .env.example .env; \
		echo "   ➜ Edit .env if you want to customize settings."; \
	fi

.PHONY: _ensure-env-prod
_ensure-env-prod:
	@if [ ! -f .env.prod ]; then \
		echo "❌ .env.prod not found!"; \
		echo "   Run: cp .env.prod.example .env.prod"; \
		echo "   Then edit it with your domain, passwords, and SMTP settings."; \
		echo "   Tip: run 'make gen-passwords' to generate strong passwords."; \
		exit 1; \
	fi

.PHONY: _check-prod-passwords
_check-prod-passwords:
	@if grep -q "CHANGE_ME" .env.prod 2>/dev/null; then \
		echo "❌ .env.prod still has CHANGE_ME placeholders!"; \
		echo "   Edit .env.prod and set real passwords."; \
		echo "   Tip: run 'make gen-passwords' to generate strong passwords."; \
		exit 1; \
	fi

.PHONY: _load-prod-env
_load-prod-env:
	@test -f .env.prod || (echo "❌ .env.prod not found!" && exit 1)

.PHONY: _ensure-hosts
_ensure-hosts:
	@if ! grep -q "passbolt.local" /etc/hosts 2>/dev/null; then \
		echo ""; \
		echo "⚠  Add this line to /etc/hosts (requires sudo):"; \
		echo "   127.0.0.1 passbolt.local"; \
		echo ""; \
		read -p "   Add it now? [y/N] " confirm; \
		if [ "$$confirm" = "y" ]; then \
			echo "127.0.0.1 passbolt.local" | sudo tee -a /etc/hosts > /dev/null; \
			echo "   ✅ Added!"; \
		fi; \
	fi

# =============================================================================
#  HELP
# =============================================================================

.PHONY: help
help: ## Show this help
	@echo ""
	@echo "  \033[1mLOCAL\033[0m"
	@grep -E '^(start|start-f|stop|restart|logs|status|create-admin|health|setup|clean|pull|update):.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  \033[1mPRODUCTION\033[0m"
	@grep -E '^[a-zA-Z_-]+-prod[a-zA-Z_-]*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  \033[1mUTILITIES\033[0m"
	@grep -E '^(vm-init|gen-passwords):.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

.DEFAULT_GOAL := help
