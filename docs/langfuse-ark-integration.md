# Langfuse Integration with ARK

This document describes how to deploy, configure, and use Langfuse with the ARK agent platform.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
- [Data Flow](#data-flow)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Integration with ARK Evaluator](#integration-with-ark-evaluator)

## Overview

Langfuse is an LLM observability platform that provides:
- **Tracing**: Track LLM calls, prompts, and responses
- **Analytics**: Monitor performance, token usage, and costs
- **Evaluation**: Integrate with ARK Evaluator for RAGAS-based assessment
- **OpenTelemetry**: Distributed tracing across services

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         ARK Platform                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐     │
│  │  ARK Agents  │───▶│ARK Evaluator │───▶│ARK Dashboard │     │
│  │              │    │              │    │              │     │
│  └──────────────┘    └──────┬───────┘    └──────────────┘     │
│                              │                                  │
│                              ▼                                  │
│  ┌──────────────────────────────────────────────────────┐      │
│  │           LangChain Executor Service                  │      │
│  │  (Processes agent requests with RAG support)         │      │
│  └──────────────────────────────────────────────────────┘      │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Langfuse Observability                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐     │
│  │ Langfuse Web │    │ Langfuse     │    │ PostgreSQL   │     │
│  │              │    │ Worker      │    │ (Metadata)   │     │
│  └──────────────┘    └──────┬───────┘    └──────┬───────┘     │
│         │                   │                   │             │
│         │                   ▼                   │             │
│         │            ┌──────────────┐             │             │
│         │            │    Redis   │             │             │
│         │            │  (Queue)   │             │             │
│         │            └──────┬──────┘             │             │
│         │                   │                   │             │
│         └───────────────────┴───────────────────┘             │
│                              │                                 │
│                              ▼                                 │
│                   ┌──────────────────────┐                     │
│                   │    ClickHouse        │                     │
│                   │   (Event Storage)    │                     │
│                   └──────────────────────┘                     │
│                              │                                 │
│                              ▼                                 │
│                   ┌──────────────────────┐                     │
│                   │   MinIO/S3 Storage    │                     │
│                   │   (File Storage)     │                     │
│                   └──────────────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Langfuse Web Service

**Purpose**: Main UI and API endpoint for Langfuse

**Responsibilities**:
- Serve the web dashboard for viewing traces
- Provide REST API for creating traces
- Handle user authentication
- Database migrations and initialization

**Key Endpoints**:
- `/api/public/traces` - Create and query traces
- `/api/public/scores` - Submit evaluation scores
- `/dashboard` - Web UI for viewing data

**Configuration**:
- **Image**: `langfuse/langfuse:3.117.2`
- **Port**: 3000
- **Database**: PostgreSQL for metadata
- **Storage**: ClickHouse for events, MinIO for files

### 2. Langfuse Worker Service

**Purpose**: Background processing for asynchronous tasks

**Responsibilities**:
- Process trace events asynchronously
- Handle batch operations
- Manage queue processing

**Configuration**:
- **Image**: `langfuse/langfuse-worker:3.117.2`
- **Port**: 3030 (monitoring)

### 3. PostgreSQL Database

**Purpose**: Store application metadata and configuration

**Responsibilities**:
- User authentication data
- Project configuration
- API keys and secrets
- Database schema migrations

**Configuration**:
- **Type**: StatefulSet
- **Password**: `changeme123`
- **Database**: `langfuse`
- **Persistent Storage**: Enabled

### 4. ClickHouse Database

**Purpose**: High-performance event storage and analytics

**Responsibilities**:
- Store trace events (prompts, completions, tokens)
- Store evaluation scores
- Provide fast analytics queries
- Historical data retention

**Configuration**:
- **Type**: StatefulSet with Zookeeper cluster
- **Shards**: 1
- **Replicas**: 1
- **Password**: `clickhouse123`

### 5. Redis Cache/Queue

**Purpose**: Task queue and caching

**Responsibilities**:
- Queue background jobs
- Cache frequently accessed data
- Session management

**Configuration**:
- **Type**: StatefulSet
- **Password**: `redis123`

### 6. MinIO (S3-compatible storage)

**Purpose**: Object storage for files and attachments

**Responsibilities**:
- Store uploaded files
- Store generated content
- Backup data

**Configuration**:
- **Access Key**: `admin`
- **Secret Key**: `password`
- **Region**: `us-east-1`

### 7. Zookeeper Cluster

**Purpose**: Coordination for ClickHouse cluster

**Responsibilities**:
- Coordinate ClickHouse replication
- Manage distributed configuration
- Leader election

**Configuration**:
- **Replicas**: 3

## Data Flow

### 1. Agent Execution Flow

```
1. User creates query in ARK Dashboard
   └─▶ Query request sent to ARK Controller

2. ARK Controller creates Query CRD
   └─▶ Assigns agent and model

3. Agent request sent to LangChain Executor
   └─▶ Executor processes with RAG support
       └─▶ Calls LLM (Azure OpenAI)
           └─▶ Returns response

4. Response sent back to ARK Controller
   └─▶ Query status updated
       └─▶ User sees response in dashboard
```

### 2. Langfuse Tracing Flow

```
1. ARK service makes LLM call
   └─▶ Creates trace in Langfuse
       ├─▶ Trace contains: session_id, user_id, metadata
       └─▶ Tracks: prompts, generations, token usage

2. Langfuse receives trace data
   ├─▶ Stores metadata in PostgreSQL
   ├─▶ Stores events in ClickHouse
   └─▶ Queues async tasks in Redis

3. Worker processes queue
   ├─▶ Enriches trace data
   ├─▶ Calculates metrics
   └─▶ Updates aggregations

4. User views in Langfuse dashboard
   └─▶ Query ClickHouse for events
       └─▶ Display traces, metrics, costs
```

### 3. Evaluation Flow

```
1. User creates evaluation in ARK Dashboard
   ├─▶ Input: Question and answer to evaluate
   ├─▶ Config: Evaluation parameters
   └─▶ Evaluator: Select evaluation method

2. Evaluation sent to ARK Evaluator
   ├─▶ Option A: Deterministic Metrics
   │   └─▶ Calculate: token usage, cost, performance
   └─▶ Option B: LLM-as-a-Judge
       ├─▶ Call LLM to assess quality
       └─▶ Score: relevance, accuracy, completeness

3. With Langfuse Provider
   ├─▶ Create trace in Langfuse
   ├─▶ Submit evaluation request
   ├─▶ Run RAGAS metrics
   └─▶ Store scores in Langfuse

4. View results
   ├─▶ In ARK Dashboard: scores and pass/fail
   └─▶ In Langfuse Dashboard: detailed traces
```

## Installation

### Prerequisites

- Kubernetes cluster (Kind, Minikube, or cloud)
- kubectl configured
- Helm 3.x installed
- `make` available

### Step 1: Install Langfuse

```bash
# From repository root
make langfuse-install
```

This command:
1. Adds Langfuse Helm repository
2. Updates chart dependencies
3. Deploys to `telemetry` namespace
4. Creates all required components

### Step 2: Verify Installation

```bash
# Check all pods are running
kubectl get pods -n telemetry

# Expected output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# langfuse-web-xxx                     1/1     Running   0          Xm
# langfuse-worker-xxx                  1/1     Running   0          Xm
# langfuse-postgresql-0                1/1     Running   0          Xm
# langfuse-clickhouse-shard0-0         1/1     Running   0          Xm
# langfuse-redis-primary-0             1/1     Running   0          Xm
# langfuse-s3-xxx                      1/1     Running   0          Xm
# langfuse-zookeeper-0                 1/1     Running   0          Xm
# langfuse-zookeeper-1                 1/1     Running   0          Xm
# langfuse-zookeeper-2                 1/1     Running   0          Xm
```

### Step 3: Access Langfuse

```bash
# Port forward to access dashboard
kubectl port-forward service/langfuse-web 3001:3000 -n telemetry &

# Or use the convenience command
make langfuse-dashboard
```

Access: http://localhost:3001

## Configuration

### Default Credentials

```yaml
Organization:
  Name: "Ark"
  ID: "ark"

Project:
  Name: "Ark"
  ID: "ark"
  Public Key: "lf_pk_1234567890"
  Secret Key: "lf_sk_1234567890"

User:
  Email: "ark@ark.com"
  Password: "password123"

Databases:
  PostgreSQL Password: "changeme123"
  ClickHouse Password: "clickhouse123"
  Redis Password: "redis123"

S3 Storage:
  Access Key: "admin"
  Secret Key: "password"
```

### Environment Variables

The Langfuse installation includes pre-configured environment variables:

```yaml
LANGFUSE_INIT_ORG_ID: "ark"
LANGFUSE_INIT_ORG_NAME: "Ark"
LANGFUSE_INIT_PROJECT_ID: "ark"
LANGFUSE_INIT_PROJECT_NAME: "Ark"
LANGFUSE_INIT_PROJECT_PUBLIC_KEY: "lf_pk_1234567890"
LANGFUSE_INIT_PROJECT_SECRET_KEY: "lf_sk_1234567890"
LANGFUSE_INIT_USER_EMAIL: "ark@ark.com"
LANGFUSE_INIT_USER_NAME: "Ark Administrators"
LANGFUSE_INIT_USER_PASSWORD: "password123"
```

### OpenTelemetry Integration

Langfuse automatically creates secrets with OTEL environment variables:

```bash
# View OTEL secrets in default namespace
kubectl get secret otel-environment-variables -n default

# View OTEL secrets in ark-system namespace
kubectl get secret otel-environment-variables -n ark-system
```

To use in deployments:

```yaml
envFrom:
- secretRef:
    name: otel-environment-variables
    optional: true
```

**Important**: Restart deployments after secret creation:

```bash
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

## Usage

### 1. Accessing the Dashboard

**URL**: http://localhost:3001

**Login**:
- Email: `ark@ark.com`
- Password: `password123`

### 2. Viewing Traces

After agents make LLM calls, traces appear in the dashboard:
1. Navigate to **Traces** section
2. See all LLM interactions
3. View prompts, responses, token usage
4. Analyze costs and performance

### 3. Using API Keys

To integrate Langfuse with your applications:

```python
from langfuse import Langfuse

langfuse = Langfuse(
    public_key="lf_pk_1234567890",
    secret_key="lf_sk_1234567890",
    host="http://localhost:3001"
)

# Create a trace
trace = langfuse.trace(name="agent-execution")

# Log a generation
generation = trace.generation(
    name="llm-call",
    model="gpt-3.5-turbo",
    model_parameters={"temperature": 0.7}
)

# Update with completion
generation.end(output="Generated response")
```

## Integration with ARK Evaluator

### Using Langfuse Provider in Evaluations

The ARK Evaluator supports Langfuse as an evaluation provider with RAGAS integration.

#### 1. Configure Evaluator with Langfuse

```yaml
apiVersion: ark.mckinsey.com/v1alpha1
kind: Evaluator
metadata:
  name: langfuse-evaluator
  namespace: default
spec:
  description: "Langfuse evaluation with RAGAS"
  address:
    valueFrom:
      serviceRef:
        name: ark-evaluator
        port: "http"
        path: "/evaluate"
  parameters:
    - name: provider
      value: "langfuse"
    - name: langfuse.host
      value: "http://langfuse-web.telemetry.svc.cluster.local:3000"
    - name: langfuse.public_key
      value: "lf_pk_1234567890"
    - name: langfuse.secret_key
      value: "lf_sk_1234567890"
```

#### 2. Create Evaluation via Dashboard

1. Go to **Evaluations** → **Create Evaluation**
2. Fill in:
   - **Name**: Your evaluation name
   - **Type**: `Direct`
   - **Evaluator**: Select Langfuse evaluator
   - **Input**: Your question
   - **Output**: Response to evaluate
3. Click **Create Evaluation**

#### 3. Evaluation Metrics Available

With Langfuse provider, you can use RAGAS metrics:

- **Relevance**: How relevant is the answer to the question
- **Correctness**: Factual correctness of the response
- **Faithfulness**: Faithfulness to the context provided
- **Context Precision**: Precision of retrieved context
- **Context Recall**: Recall of context relative to ground truth
- **Similarity**: Semantic similarity between answers

### API-based Evaluation

```bash
curl -X POST http://localhost:8001/evaluate \
  -H "Content-Type: application/json" \
  -d '{
    "type": "direct",
    "config": {
      "input": "What is machine learning?",
      "output": "Machine learning is a subset of AI..."
    },
    "parameters": {
      "provider": "langfuse",
      "langfuse.host": "http://langfuse-web.telemetry.svc.cluster.local:3000",
      "langfuse.public_key": "lf_pk_1234567890",
      "metrics": "relevance,correctness,faithfulness",
      "threshold": "0.8"
    }
  }'
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n telemetry

# View logs
kubectl logs <pod-name> -n telemetry

# Describe pod for events
kubectl describe pod <pod-name> -n telemetry
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
kubectl get pod langfuse-postgresql-0 -n telemetry

# Check logs
kubectl logs langfuse-postgresql-0 -n telemetry

# Verify connectivity
kubectl exec -it langfuse-web-xxx -n telemetry -- nc -zv langfuse-postgresql 5432
```

### Port Forward Not Working

```bash
# Check service exists
kubectl get svc langfuse-web -n telemetry

# Kill existing port forwards
killall kubectl

# Start fresh
kubectl port-forward service/langfuse-web 3001:3000 -n telemetry
```

### Getting Credentials

```bash
# Use the convenience command
make langfuse-credentials

# Or manually get from secret
kubectl get secret langfuse-env -n telemetry -o yaml
```

## Summary

Langfuse provides comprehensive LLM observability for the ARK platform:

- **Tracing**: Track all agent interactions and LLM calls
- **Analytics**: Monitor performance, costs, and token usage
- **Evaluation**: Integrated RAGAS evaluation with ARK Evaluator
- **OpenTelemetry**: Distributed tracing across services

All components are deployed and running in the `telemetry` namespace, with persistent storage for long-term analytics.

