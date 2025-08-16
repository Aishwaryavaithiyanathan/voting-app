# Voting App with Docker Swarm

This is a microservices-based voting application deployed using **Docker Swarm**.

## Services
- Vote (Python/Flask frontend) → Port 5000
- Redis (in-memory store)
- Worker (background processor)
- DB (Postgres)
- Result (Node.js frontend) → Port 5001
- Visualizer (Swarm visualization) → Port 8080

## Deployment

```bash
docker stack deploy -c docker-stack.yml voting_app
docker service ls

