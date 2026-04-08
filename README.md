# 🔐 Passbolt Local + Production

Self-hosted [Passbolt CE](https://www.passbolt.com/) password manager — one command to start locally, one command to deploy to a VM.

## Prerequisites

- **Docker** & **Docker Compose** v2+
- A browser with the [Passbolt extension](https://www.passbolt.com/download) (Firefox, Chrome, Edge, Brave)

## Local (dev)

```bash
make setup        # Creates .env, adds /etc/hosts, starts, creates admin
```

Or step by step:

```bash
make start        # Background
make start-f      # Foreground (follow logs)
make create-admin # Create first admin user
```

Open **https://passbolt.local:8443** → accept self-signed cert → follow the setup link.

## Production (VM)

### 1. Provision a VM

Any Ubuntu 22.04/24.04 VPS works (OVH, Hetzner, DigitalOcean, etc.). Clone the repo on it, then:

```bash
make vm-init      # Installs Docker + configures UFW firewall
# Log out & back in (docker group)
```

### 2. Configure

```bash
cp .env.prod.example .env.prod
make gen-passwords                # Generate strong DB passwords
nano .env.prod                    # Set DOMAIN, passwords, SMTP
```

Point your domain's **A record** → VM public IP before proceeding.

### 3. Launch

```bash
make setup-prod   # Starts Traefik + Passbolt, obtains SSL, creates admin
```

Traefik automatically obtains and renews Let's Encrypt certificates.

## All Commands

### Local

| Command            | Description                         |
|--------------------|-------------------------------------|
| `make start`       | Start in background                 |
| `make start-f`     | Start in foreground                 |
| `make stop`        | Stop                                |
| `make restart`     | Restart                             |
| `make logs`        | Tail logs                           |
| `make status`      | Container status                    |
| `make create-admin`| Register first admin                |
| `make health`      | Healthcheck                         |
| `make update`      | Pull latest images & restart        |
| `make clean`       | ⚠ Remove containers + data          |

### Production

| Command               | Description                           |
|-----------------------|---------------------------------------|
| `make start-prod`     | Start in background                   |
| `make start-prod-f`   | Start in foreground                   |
| `make stop-prod`      | Stop                                  |
| `make restart-prod`   | Restart                               |
| `make logs-prod`      | Tail logs                             |
| `make status-prod`    | Container status                      |
| `make create-admin-prod` | Register first admin               |
| `make health-prod`    | Healthcheck                           |
| `make update-prod`    | Pull latest images & restart          |
| `make backup-prod`    | Backup DB + GPG + JWT keys            |
| `make clean-prod`     | ⚠ Remove everything (type DELETE)     |

### Utilities

| Command              | Description                          |
|----------------------|--------------------------------------|
| `make vm-init`       | Bootstrap Docker + UFW on Ubuntu VM  |
| `make gen-passwords` | Generate strong random passwords     |
| `make help`          | Show all commands                    |

## Architecture

```
Local:
  passbolt (self-signed :443) ← browser
  └── mariadb

Production:
  traefik (:80/:443, Let's Encrypt) ← browser
  └── passbolt (internal)
      └── mariadb
```

## Backups

```bash
make backup-prod   # → backups/db_YYYYMMDD_HHMMSS.sql
                   #   backups/gpg_YYYYMMDD_HHMMSS/
                   #   backups/jwt_YYYYMMDD_HHMMSS/
```

## Data Volumes

- `db_data` — MariaDB database
- `gpg_data` — GPG server keys (critical — backup these!)
- `jwt_data` — JWT authentication keys
- `letsencrypt_data` — SSL certificates (prod only)

## License

Passbolt CE is open source under AGPL-3.0. This repo is a convenience wrapper.
