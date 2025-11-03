# Langfuse in ARK - Quick Reference Guide

## Installation Commands

```bash
# Install Langfuse
make langfuse-install

# Show credentials
make langfuse-credentials

# Start dashboard
make langfuse-dashboard

# Uninstall
make langfuse-uninstall
```

## Access Information

| Service | URL | Credentials |
|---------|-----|-------------|
| **Dashboard** | http://localhost:3001 | ark@ark.com / password123 |
| **API** | http://langfuse-web.telemetry.svc.cluster.local:3000 | N/A |
| **Internal** | langfuse-web.telemetry:3000 | N/A |

## API Keys

```yaml
Public Key:  lf_pk_1234567890
Secret Key:  lf_sk_1234567890
```

## Components

### Pods (telemetry namespace)

```bash
kubectl get pods -n telemetry

# Expected:
# langfuse-web-xxx             1/1   Running
# langfuse-worker-xxx          1/1   Running  
# langfuse-postgresql-0        1/1   Running
# langfuse-clickhouse-shard0-0 1/1   Running
# langfuse-redis-primary-0     1/1   Running
# langfuse-s3-xxx              1/1   Running
# langfuse-zookeeper-0         1/1   Running
# langfuse-zookeeper-1         1/1   Running
# langfuse-zookeeper-2         1/1   Running
```

### Services

```bash
kubectl get svc -n telemetry

# Key services:
# langfuse-web           ClusterIP  3000/TCP
# langfuse-clickhouse    ClusterIP  8123,9000,9004,9005,9009/TCP
# langfuse-postgresql    ClusterIP  5432/TCP
# langfuse-redis-primary ClusterIP  6379/TCP
# langfuse-s3            ClusterIP  9000,9001/TCP
```

## Database Passwords

```yaml
PostgreSQL: changeme123
ClickHouse: clickhouse123
Redis:      redis123
S3/MinIO:   admin / password
```

## Troubleshooting

### Pods not starting

```bash
# View pod logs
kubectl logs <pod-name> -n telemetry

# Describe pod
kubectl describe pod <pod-name> -n telemetry

# Check events
kubectl get events -n telemetry --sort-by='.lastTimestamp'
```

### Database connection issues

```bash
# Test PostgreSQL
kubectl exec -it langfuse-postgresql-0 -n telemetry -- psql -U postgres

# Test ClickHouse
kubectl port-forward langfuse-clickhouse-shard0-0 8123:8123 -n telemetry
curl http://localhost:8123/ping

# Test Redis
kubectl exec -it langfuse-redis-primary-0 -n telemetry -- redis-cli -a redis123 ping
```

### Restart services

```bash
# Restart web
kubectl rollout restart deployment/langfuse-web -n telemetry

# Restart worker
kubectl rollout restart deployment/langfuse-worker -n telemetry

# Check status
kubectl rollout status deployment/langfuse-web -n telemetry
```

## Python Integration

```python
from langfuse import Langfuse

# Initialize
langfuse = Langfuse(
    public_key="lf_pk_1234567890",
    secret_key="lf_sk_1234567890",
    host="http://langfuse-web.telemetry.svc.cluster.local:3000"
)

# Create trace
trace = langfuse.trace(
    name="agent-execution",
    user_id="user-123",
    metadata={"agent": "my-agent"}
)

# Log generation
generation = trace.generation(
    name="llm-call",
    model="gpt-3.5-turbo",
    model_parameters={"temperature": 0.7}
)

# Update with input/output
generation.update(
    input="What is AI?",
    output="AI is artificial intelligence",
    usage={"promptTokens": 10, "completionTokens": 5, "totalTokens": 15}
)
generation.end()

# Submit score
trace.score(
    name="relevance",
    value=0.95,
    comment="High relevance"
)
```

## cURL Examples

### Create Trace

```bash
curl -X POST http://localhost:3001/api/public/traces \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer lf_sk_1234567890" \
  -d '{
    "name": "test-trace",
    "userId": "user-123",
    "metadata": {"type": "agent-execution"}
  }'
```

### Get Traces

```bash
curl http://localhost:3001/api/public/traces \
  -H "Authorization: Bearer lf_sk_1234567890"
```

## Common Issues

### Issue: Web pod in Error state

```bash
# Delete pod to force restart
kubectl delete pod langfuse-web-xxx -n telemetry

# Wait for new pod
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=langfuse -n telemetry

# Check logs
kubectl logs langfuse-web-xxx -n telemetry
```

### Issue: Can't connect to database

```bash
# Check PostgreSQL is ready
kubectl get pod langfuse-postgresql-0 -n telemetry

# Test connection from web pod
kubectl exec -it langfuse-web-xxx -n telemetry -- nc -zv langfuse-postgresql 5432
```

### Issue: Port forward not working

```bash
# Kill existing port forwards
killall kubectl

# Start fresh
kubectl port-forward service/langfuse-web 3001:3000 -n telemetry &
```

## Viewing Data

### In Dashboard

1. Open http://localhost:3001
2. Login with ark@ark.com / password123
3. Navigate to:
   - **Traces**: View all LLM interactions
   - **Sessions**: Grouped interactions
   - **Analytics**: Performance and costs
   - **Projects**: Project settings

### Via API

```bash
# List all traces
curl http://localhost:3001/api/public/traces \
  -H "Authorization: Bearer lf_sk_1234567890"

# Get specific trace
curl http://localhost:3001/api/public/traces/{id} \
  -H "Authorization: Bearer lf_sk_1234567890"
```

## Integration with ARK

### In Evaluator Request

```json
{
  "type": "direct",
  "config": {
    "input": "What is AI?",
    "output": "AI is artificial intelligence"
  },
  "parameters": {
    "provider": "langfuse",
    "langfuse.host": "http://langfuse-web.telemetry.svc.cluster.local:3000",
    "langfuse.public_key": "lf_pk_1234567890",
    "langfuse.secret_key": "lf_sk_1234567890",
    "metrics": "relevance,correctness,faithfulness",
    "threshold": "0.8"
  }
}
```

### In Agent Configuration

Add OTEL environment variables to agent deployments:

```yaml
envFrom:
- secretRef:
    name: otel-environment-variables
    optional: true
```

Then restart the deployment:

```bash
kubectl rollout restart deployment/<agent-deployment> -n <namespace>
```

## Useful Commands

```bash
# Check all Langfuse resources
kubectl get all -n telemetry

# View logs for web service
kubectl logs -f deployment/langfuse-web -n telemetry

# View logs for worker
kubectl logs -f deployment/langfuse-worker -n telemetry

# Access PostgreSQL
kubectl exec -it langfuse-postgresql-0 -n telemetry -- psql -U postgres -d langfuse

# Access ClickHouse
kubectl exec -it langfuse-clickhouse-shard0-0 -n telemetry -- clickhouse-client

# Access Redis
kubectl exec -it langfuse-redis-primary-0 -n telemetry -- redis-cli -a redis123
```

## Performance Monitoring

### Check Resource Usage

```bash
# View pod resource usage
kubectl top pods -n telemetry

# View node resource usage
kubectl top nodes
```

### Database Sizes

```bash
# PostgreSQL size
kubectl exec -it langfuse-postgresql-0 -n telemetry -- \
  psql -U postgres -d langfuse -c \
  "SELECT pg_size_pretty(pg_database_size('langfuse'));"

# ClickHouse size
kubectl exec -it langfuse-clickhouse-shard0-0 -n telemetry -- \
  clickhouse-client --query "SELECT formatReadableSize(sum(bytes)) FROM system.tables WHERE database='langfuse'"
```

## Backup and Restore

### Backup PostgreSQL

```bash
kubectl exec langfuse-postgresql-0 -n telemetry -- \
  pg_dump -U postgres langfuse > backup.sql
```

### Restore PostgreSQL

```bash
kubectl exec -i langfuse-postgresql-0 -n telemetry -- \
  psql -U postgres langfuse < backup.sql
```

