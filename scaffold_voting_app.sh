#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash scaffold_voting_app.sh <github_username_or_org> <registry_namespace>
# Example (Docker Hub):
#   bash scaffold_voting_app.sh aishwarya docker.io/aishwarya
# Example (GHCR):
#   bash scaffold_voting_app.sh aishwarya ghcr.io/aishwarya

GITHUB_USER=${1:-your-github-username}
REGISTRY=${2:-docker.io/${GITHUB_USER}}

REPO_DIR="voting-app"

mkdir -p "$REPO_DIR" && cd "$REPO_DIR"

echo "Creating repository structure..."
mkdir -p vote worker result db redis visualizer .github/workflows

########################################
# .gitignore
########################################
cat > .gitignore <<'EOF'
# Python
__pycache__/
*.pyc
.venv/

# Node
node_modules/

# Docker
*.env
.env*
EOF

########################################
# Top-level README
########################################
cat > README.md <<'EOF'
# Voting App (Docker Swarm Microservices)

A simple microservices-based voting application built from source and containerized with Docker.

**Services**
- **vote**: Python/Flask UI to cast a vote (talks to Redis)
- **worker**: Python worker consuming Redis queue and writing tallies to Postgres
- **result**: Node/Express UI showing live results from Postgres
- **redis**: In-memory queue
- **db**: Postgres with init SQL
- **visualizer**: Swarm visualizer (manager only)

## Quick start (Compose - local/dev)
```bash
# Build
docker compose build

# Run
docker compose up -d

# Apps
# Vote UI:   http://localhost:5000
# Result UI: http://localhost:5001
# Visualizer: http://localhost:8080 (only if running in Swarm; see below)
```

## Deploy to Docker Swarm
```bash
# Create a secret for DB password
printf 'postgres' | docker secret create voting_db_password -

# Deploy
docker stack deploy -c docker-stack.yml voting

# Inspect
docker stack services voting
```

## Build & Push (adjust REGISTRY in docker-compose and docker-stack)
```bash
# Docker Hub login
# docker login -u <username>

# Build images
docker build -t $REGISTRY/vote:1.0 ./vote
docker build -t $REGISTRY/worker:1.0 ./worker
docker build -t $REGISTRY/result:1.0 ./result

# Push
docker push $REGISTRY/vote:1.0
docker push $REGISTRY/worker:1.0
docker push $REGISTRY/result:1.0
```
EOF

########################################
# .env (used by compose locally)
########################################
cat > .env <<'EOF'
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=voting
REDIS_HOST=redis
DB_HOST=db
DB_PORT=5432
EOF

########################################
# docker-compose.yml (local/dev)
########################################
cat > docker-compose.yml <<EOF
version: "3.9"
services:
  vote:
    build: ./vote
    image: ${REGISTRY}/vote:1.0
    environment:
      - REDIS_HOST=\${REDIS_HOST}
    ports:
      - "5000:80"
    depends_on:
      - redis
    networks: [frontend, backend]

  worker:
    build: ./worker
    image: ${REGISTRY}/worker:1.0
    environment:
      - REDIS_HOST=\${REDIS_HOST}
      - DB_HOST=\${DB_HOST}
      - DB_PORT=\${DB_PORT}
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
    depends_on:
      - redis
      - db
    networks: [backend]

  result:
    build: ./result
    image: ${REGISTRY}/result:1.0
    environment:
      - DB_HOST=\${DB_HOST}
      - DB_PORT=\${DB_PORT}
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
    ports:
      - "5001:80"
    depends_on:
      - db
    networks: [backend]

  redis:
    image: redis:7-alpine
    networks: [backend]

  db:
    build: ./db
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
    volumes:
      - db_data:/var/lib/postgresql/data
    networks: [backend]

networks:
  frontend:
  backend:

volumes:
  db_data:
EOF

########################################
# docker-stack.yml (Swarm)
########################################
cat > docker-stack.yml <<EOF
version: "3.9"

networks:
  frontend:
    driver: overlay
  backend:
    driver: overlay

secrets:
  voting_db_password:
    external: true

volumes:
  db_data:

services:
  vote:
    image: ${REGISTRY}/vote:1.0
    environment:
      - REDIS_HOST=redis
    ports:
      - "5000:80"
    networks: [frontend, backend]
    deploy:
      replicas: 3
      restart_policy: { condition: on-failure }
      update_config: { parallelism: 1, order: start-first, delay: 10s }

  worker:
    image: ${REGISTRY}/worker:1.0
    environment:
      - REDIS_HOST=redis
      - DB_HOST=db
      - DB_PORT=5432
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD_FILE=/run/secrets/voting_db_password
      - POSTGRES_DB=voting
    secrets: [voting_db_password]
    networks: [backend]
    deploy:
      replicas: 2
      restart_policy: { condition: on-failure }

  result:
    image: ${REGISTRY}/result:1.0
    environment:
      - DB_HOST=db
      - DB_PORT=5432
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD_FILE=/run/secrets/voting_db_password
      - POSTGRES_DB=voting
    ports:
      - "5001:80"
    secrets: [voting_db_password]
    networks: [backend]
    deploy:
      replicas: 2
      restart_policy: { condition: on-failure }

  redis:
    image: redis:7-alpine
    networks: [backend]
    deploy:
      replicas: 1

  db:
    image: ${REGISTRY}/db:1.0
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD_FILE=/run/secrets/voting_db_password
      - POSTGRES_DB=voting
    secrets: [voting_db_password]
    volumes:
      - db_data:/var/lib/postgresql/data
    networks: [backend]
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager

  visualizer:
    image: dockersamples/visualizer:latest
    ports:
      - "8080:8080"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    networks: [frontend]
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOF

########################################
# vote service
########################################
cat > vote/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py ./
ENV FLASK_ENV=production
EXPOSE 80
CMD ["gunicorn", "-b", "0.0.0.0:80", "app:app"]
EOF

cat > vote/requirements.txt <<'EOF'
flask==3.0.3
redis==5.0.7
gunicorn==22.0.0
EOF

cat > vote/app.py <<'EOF'
from flask import Flask, render_template_string, request, redirect
import os
import redis

app = Flask(__name__)
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
r = redis.Redis(host=REDIS_HOST, port=6379, db=0)

tpl = """
<!doctype html>
<title>Voting App</title>
<h1>Cast your vote</h1>
<form method="post" action="/vote">
  <button name="vote" value="cats">Cats</button>
  <button name="vote" value="dogs">Dogs</button>
</form>
<p><a href="/health">health</a> | <a href="/">home</a></p>
"""

@app.get("/")
def index():
    return render_template_string(tpl)

@app.get("/health")
def health():
    try:
        r.ping()
        return {"status": "ok"}
    except Exception as e:
        return {"status": "error", "detail": str(e)}, 500

@app.post("/vote")
def vote():
    v = request.form.get("vote")
    if v not in ("cats", "dogs"):
        return redirect("/")
    r.lpush("votes", v)
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
EOF

########################################
# worker service
########################################
cat > worker/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY worker.py ./
CMD ["python", "worker.py"]
EOF

cat > worker/requirements.txt <<'EOF'
redis==5.0.7
psycopg2-binary==2.9.9
EOF

cat > worker/worker.py <<'EOF'
import os
import time
import redis
import psycopg2

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
DB_HOST = os.getenv("DB_HOST", "db")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("POSTGRES_DB", "voting")
DB_USER = os.getenv("POSTGRES_USER", "postgres")
DB_PASS = os.getenv("POSTGRES_PASSWORD", None)
DB_PASS_FILE = os.getenv("POSTGRES_PASSWORD_FILE")

if DB_PASS is None and DB_PASS_FILE and os.path.exists(DB_PASS_FILE):
    with open(DB_PASS_FILE) as f:
        DB_PASS = f.read().strip()

r = redis.Redis(host=REDIS_HOST, port=6379, db=0)

def get_conn():
    while True:
        try:
            return psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASS)
        except Exception as e:
            print("Waiting for database...", e)
            time.sleep(2)

def ensure_table(conn):
    with conn.cursor() as cur:
        cur.execute("""
        CREATE TABLE IF NOT EXISTS votes (
            option TEXT PRIMARY KEY,
            count  INTEGER NOT NULL DEFAULT 0
        );
        """)
        conn.commit()


def increment_vote(conn, choice):
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO votes(option, count) VALUES (%s, 1)
            ON CONFLICT(option) DO UPDATE SET count = votes.count + 1
            """,
            (choice,)
        )
        conn.commit()


def main():
    conn = get_conn()
    ensure_table(conn)
    print("Worker started; waiting for votes...")
    while True:
        try:
            _, val = r.brpop("votes")  # blocking pop
            choice = val.decode("utf-8")
            if choice in ("cats", "dogs"):
                increment_vote(conn, choice)
                print(f"counted: {choice}")
        except Exception as e:
            print("Error processing vote:", e)
            time.sleep(1)

if __name__ == "__main__":
    main()
EOF

########################################
# result service (Node/Express)
########################################
cat > result/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev || npm install --omit=dev
COPY server.js ./
EXPOSE 80
CMD ["node", "server.js"]
EOF

cat > result/package.json <<'EOF'
{
  "name": "result",
  "version": "1.0.0",
  "main": "server.js",
  "license": "MIT",
  "dependencies": {
    "express": "^4.19.2",
    "pg": "^8.11.5"
  }
}
EOF

cat > result/server.js <<'EOF'
const express = require('express');
const { Pool } = require('pg');

const app = express();
const PORT = 80;

const cfg = {
  host: process.env.DB_HOST || 'db',
  port: +(process.env.DB_PORT || 5432),
  user: process.env.POSTGRES_USER || 'postgres',
  password: process.env.POSTGRES_PASSWORD,
  database: process.env.POSTGRES_DB || 'voting'
};

if (!cfg.password && process.env.POSTGRES_PASSWORD_FILE) {
  const fs = require('fs');
  try { cfg.password = fs.readFileSync(process.env.POSTGRES_PASSWORD_FILE, 'utf8').trim(); } catch {}
}

const pool = new Pool(cfg);

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok' });
  } catch (e) {
    res.status(500).json({ status: 'error', detail: String(e) });
  }
});

app.get('/', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT option, count FROM votes ORDER BY option');
    const counts = Object.fromEntries(rows.map(r => [r.option, r.count]));
    const cats = counts.cats || 0;
    const dogs = counts.dogs || 0;
    res.send(`<!doctype html><title>Results</title>
      <h1>Results</h1>
      <p>Cats: <b>${cats}</b></p>
      <p>Dogs: <b>${dogs}</b></p>
      <p><a href="/health">health</a></p>`);
  } catch (e) {
    res.status(500).send('DB error: ' + String(e));
  }
});

app.listen(PORT, () => console.log(`Result UI on :${PORT}`));
EOF

########################################
# db image (extends Postgres with init script)
########################################
cat > db/Dockerfile <<'EOF'
FROM postgres:15-alpine
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql
EOF

cat > db/init.sql <<'EOF'
CREATE TABLE IF NOT EXISTS votes (
    option TEXT PRIMARY KEY,
    count  INTEGER NOT NULL DEFAULT 0
);
INSERT INTO votes(option, count) VALUES ('cats', 0) ON CONFLICT DO NOTHING;
INSERT INTO votes(option, count) VALUES ('dogs', 0) ON CONFLICT DO NOTHING;
EOF

########################################
# redis (placeholder for customizations)
########################################
cat > redis/README.md <<'EOF'
Using official image: redis:7-alpine.
Customize here if you need persistence or custom config.
EOF

########################################
# Visualizer note
########################################
cat > visualizer/README.md <<'EOF'
Using image dockersamples/visualizer. Runs only on Swarm manager.
EOF

########################################
# GitHub Actions (optional) – build on push
########################################
cat > .github/workflows/docker-build.yml <<'EOF'
name: Build Images
on:
  push:
    branches: [ main, master ]
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      - name: Login to Docker Hub (optional)
        if: env.DOCKERHUB_USERNAME != ''
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - name: Build vote
        uses: docker/build-push-action@v6
        with:
          context: ./vote
          push: false
          tags: vote:ci
      - name: Build worker
        uses: docker/build-push-action@v6
        with:
          context: ./worker
          push: false
          tags: worker:ci
      - name: Build result
        uses: docker/build-push-action@v6
        with:
          context: ./result
          push: false
          tags: result:ci
EOF

########################################
# Final instructions
echo "\nScaffold complete. Next steps:"
echo "1) git init && git remote add origin git@github.com:${GITHUB_USER}/voting-app.git && git add . && git commit -m 'Initial commit' && git push -u origin main"
echo "2) Build locally: docker compose build && docker compose up -d"
echo "3) For Swarm: create secret, build & push images to ${REGISTRY}, then: docker stack deploy -c docker-stack.yml voting"
