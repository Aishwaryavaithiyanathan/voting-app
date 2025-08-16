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
