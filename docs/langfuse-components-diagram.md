# Langfuse in ARK - Components and Process Flow

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ARK PLATFORM                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │                        ARK Dashboard                               │   │
│  │  • Create Agents                                                   │   │
│  │  • Create Queries                                                  │   │
│  │  • View Evaluations                                                │   │
│  │  • Monitor Performance                                             │   │
│  └───────────────────┬──────────────────────────────────────────────┘   │
│                      │                                                      │
│                      ▼                                                      │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │                      ARK Controller                                │   │
│  │  • Manages Query CRDs                                              │   │
│  │  • Routes to Executors                                             │   │
│  │  • Updates Query Status                                            │   │
│  └──────┬─────────────────────┬───────────────────┬─────────────────┘   │
│         │                     │                     │                      │
│         ▼                     ▼                     ▼                      │
│  ┌─────────────┐    ┌──────────────────┐    ┌──────────────┐            │
│  │  ARK API    │    │ ARK Evaluator    │    │ LangChain    │            │
│  │             │    │                  │    │ Executor     │            │
│  │ • REST API  │    │ • LLM Evaluation │    │ • Agent Exec │            │
│  │ • MCP       │    │ • Metrics        │    │ • RAG Support │            │
│  └─────────────┘    └──────────────────┘    └──────┬───────┘            │
│                                                     │                     │
└─────────────────────────────────────────────────────┼─────────────────────┘
                                                      │
                                                      │ LLM Calls
                                                      ▼
                                            ┌─────────────────┐
                                            │  Azure OpenAI    │
                                            │  Model API       │
                                            └────────┬──────────┘
                                                     │
                                           ┌─────────┴──────────┐
                                           │                    │
                                           ▼                    ▼
                            ┌──────────────────────┐  ┌──────────────────┐
                            │   Trace Data         │  │  Response Data   │
                            │   - Prompts          │  │  - Completions   │
                            │   - Token Usage      │  │  - Metadata      │
                            │   - Costs            │  │  - Performance   │
                            └──────────────────────┘  └──────────────────┘
                                           │                    │
                                           └─────────┬──────────┘
                                                     ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                       LANGFUSE OBSERVABILITY                              │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                    Langfuse Web Service                           │ │
│  │  • Dashboard UI                                                   │ │
│  │  • REST API                                                       │ │
│  │  • Authentication                                                 │ │
│  │  • Database Migrations                                            │ │
│  │  Port: 3000                                                       │ │
│  └────────────────────────┬──────────────────────────────────────────┘ │
│                           │                                             │
│                           ▼                                             │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                    Langfuse Worker                                 │ │
│  │  • Background Processing                                          │ │
│  │  • Queue Management                                               │ │
│  │  • Event Processing                                               │ │
│  │  Port: 3030                                                       │ │
│  └────────────────────────┬──────────────────────────────────────────┘ │
│                           │                                             │
│                           ▼                                             │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                         Redis Cache                                │ │
│  │  • Task Queue                                                     │ │
│  │  • Caching                                                         │ │
│  │  • Session Management                                             │ │
│  │  Password: redis123                                                 │ │
│  └────────────────────────┬──────────────────────────────────────────┘ │
│                           │                                             │
│           ┌───────────────┴───────────────┐                            │
│           │                               │                            │
│           ▼                               ▼                            │
│  ┌──────────────────┐         ┌──────────────────────┐               │
│  │  PostgreSQL      │         │   ClickHouse          │               │
│  │                  │         │                       │               │
│  │ • User Data      │         │ • Trace Events        │               │
│  │ • Projects       │         │ • Analytics           │               │
│  │ • API Keys       │         │ • Metrics              │               │
│  │ • Configuration │         │ • Performance Data     │               │
│  │ Password:        │         │ Password:              │               │
│  │ changeme123      │         │ clickhouse123          │               │
│  └──────────────────┘         └──────────────────────┘               │
│           │                               │                            │
│           └───────────────┬───────────────┘                            │
│                           │                                             │
│                           ▼                                             │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                    MinIO/S3 Storage                                │ │
│  │  • File Storage                                                    │ │
│  │  • Attachments                                                     │ │
│  │  • Generated Content                                               │ │
│  │  Access Key: admin                                                 │ │
│  │  Secret Key: password                                               │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Sequence

### 1. User Creates Query

```
User (ARK Dashboard)
  │
  ├─ Create Agent
  │  └─ Agent CRD created in Kubernetes
  │
  ├─ Create Query
  │  └─ Query CRD created with agent reference
  │     ├─ Status: pending
  │     └─ Assigned to LangChain Executor
  │
  └─ Submit Query
     └─ ARK Controller processes
```

### 2. Agent Execution

```
ARK Controller
  │
  ├─ Validate Query CRD
  │
  ├─ Select Executor (LangChain Executor)
  │
  ├─ Send Execution Request
  │  └─ POST /execute
  │     ├─ Agent config
  │     ├─ User input
  │     └─ History
  │
  └─ Monitor Execution
```

### 3. LangChain Processing with RAG

```
LangChain Executor
  │
  ├─ Parse Agent Config
  │  ├─ Model: azure-openai
  │  ├─ Prompt: Custom instructions
  │  └─ RAG: Enabled (optional)
  │
  ├─ RAG Processing (if enabled)
  │  ├─ Index code files
  │  ├─ Create embeddings
  │  ├─ Vector search (FAISS)
  │  └─ Retrieve relevant context
  │
  ├─ Prepare Messages
  │  ├─ System message (prompt)
  │  ├─ History messages
  │  ├─ User message + RAG context
  │  └─ Tools (if any)
  │
  └─ Call LLM (Azure OpenAI)
     ├─ Send request
     ├─ Receive response
     └─ Parse output
```

### 4. Tracing to Langfuse

```
During LLM Call
  │
  ├─ Capture Trace Data
  │  ├─ Session ID
  │  ├─ User ID
  │  ├─ Model: azure-openai
  │  ├─ Prompt + context
  │  ├─ Response
  │  ├─ Token counts
  │  └─ Cost calculation
  │
  ├─ Send to Langfuse
  │  └─ POST /api/public/traces
  │     └─ JSON payload
  │
  └─ Langfuse Processing
     ├─ Store in PostgreSQL (metadata)
     ├─ Store in ClickHouse (events)
     └─ Queue worker tasks
```

### 5. Response Handling

```
LangChain Executor
  │
  ├─ Parse LLM Response
  │
  ├─ Create Response Messages
  │
  ├─ Return to ARK Controller
  │  └─ Update Query CRD
  │     ├─ Status: completed
  │     ├─ Output: response
  │     └─ Metadata
  │
  └─ Display in Dashboard
     └─ User sees response
```

### 6. Evaluation (Optional)

```
If Evaluation Triggered
  │
  ├─ ARK Evaluator
  │  ├─ Type: direct/query/batch/event
  │  ├─ Input: question
  │  ├─ Output: response
  │  └─ Provider: langfuse
  │
  ├─ Langfuse Provider Processing
  │  ├─ Create trace in Langfuse
  │  ├─ Submit to Langfuse API
  │  ├─ Run RAGAS metrics
  │  │  ├─ Relevance
  │  │  ├─ Correctness
  │  │  ├─ Faithfulness
  │  │  └─ Context metrics
  │  └─ Store scores
  │
  ├─ Return Results
  │  ├─ Scores per metric
  │  ├─ Pass/Fail status
  │  └─ Detailed reasoning
  │
  └─ Store Results
     ├─ Query CRD updated
     └─ Langfuse trace updated
```

## Component Details

### Langfuse Web Service

**Purpose**: Main API and UI server

**Responsibilities**:
- Serve web dashboard
- Handle API requests for traces
- User authentication
- Database migrations

**Endpoints**:
- `GET /` - Dashboard UI
- `POST /api/public/traces` - Create traces
- `GET /api/public/traces/{id}` - Get trace
- `POST /api/public/scores` - Submit scores

### Langfuse Worker Service

**Purpose**: Asynchronous processing

**Responsibilities**:
- Process trace events from queue
- Calculate aggregations
- Handle batch operations
- Background tasks

**Queue**: Redis

### PostgreSQL

**Purpose**: Application database

**Storage**:
- Users and authentication
- Projects and organizations
- API keys
- Settings
- Database schema

**Tables**:
- `users`
- `projects`
- `api_keys`
- `sessions`

### ClickHouse

**Purpose**: High-performance analytics database

**Storage**:
- Trace events
- Prompt/response data
- Token counts
- Cost data
- Timestamps

**Performance**:
- Fast inserts
- Columnar storage
- Efficient queries
- Compression

### Redis

**Purpose**: Queue and cache

**Usage**:
- Job queue for workers
- Cache frequently accessed data
- Session storage
- Rate limiting

### MinIO/S3

**Purpose**: Object storage

**Storage**:
- Uploaded files
- Generated attachments
- Backup files

**Compatibility**: Amazon S3 compatible

### Zookeeper Cluster

**Purpose**: ClickHouse coordination

**Usage**:
- Cluster coordination
- Leader election
- Configuration management
- Replication control

**Cluster Size**: 3 nodes (leader + 2 followers)

## Network Topology

```
Internet
  │
  └─▶ Port Forward (localhost)
      │
      ├─▶ :3000 → ARK Dashboard
      ├─▶ :3001 → Langfuse Web
      ├─▶ :8001 → ARK Evaluator
      └─▶ :8002 → LangChain Executor

Within Kubernetes Cluster:
  
  namespace: default
  ├─▶ ark-api (ClusterIP: 80)
  ├─▶ ark-evaluator (ClusterIP: 8000)
  ├─▶ executor-langchain (ClusterIP: 8000)
  └─▶ azure-openai model

  namespace: telemetry
  ├─▶ langfuse-web (ClusterIP: 3000)
  ├─▶ langfuse-worker (ClusterIP: 3030)
  ├─▶ langfuse-postgresql (ClusterIP: 5432)
  ├─▶ langfuse-clickhouse (ClusterIP: 8123, 9000, 9004, 9005, 9009)
  ├─▶ langfuse-redis-primary (ClusterIP: 6379)
  ├─▶ langfuse-s3 (ClusterIP: 9000, 9001)
  └─▶ langfuse-zookeeper (ClusterIP: 2181, 2888, 3888)

Internal DNS:
  • langfuse-web.telemetry.svc.cluster.local:3000
  • ark-evaluator.default.svc.cluster.local:8000
  • executor-langchain.default.svc.cluster.local:8000
```

## Configuration Reference

### Environment Variables

**Langfuse Web/Worker**:
```yaml
# Database
DATABASE_URL: postgresql://postgres:changeme123@langfuse-postgresql:5432/langfuse

# Redis
REDIS_URL: redis://:redis123@langfuse-redis-primary:6379

# ClickHouse
CLICKHOUSE_URL: http://langfuse-clickhouse:8123
CLICKHOUSE_PASSWORD: clickhouse123

# S3/MinIO
AWS_ACCESS_KEY_ID: admin
AWS_SECRET_ACCESS_KEY: password
AWS_ENDPOINT_URL_S3: http://langfuse-s3:9000
AWS_REGION: us-east-1

# Secrets
NEXTAUTH_SECRET: langfuse-nextauth-secret-change-me
LANGFUSE_SALT: langfuse-salt-local-development-mode
LANGFUSE_ENCRYPTION_KEY: cdd693af5b1ced98097c45550ea34f374fdd8d3427aa2a6a96a2204017a8caf3

# Initialization
LANGFUSE_INIT_ORG_ID: ark
LANGFUSE_INIT_ORG_NAME: Ark
LANGFUSE_INIT_PROJECT_ID: ark
LANGFUSE_INIT_PROJECT_NAME: Ark
LANGFUSE_INIT_PROJECT_PUBLIC_KEY: lf_pk_1234567890
LANGFUSE_INIT_PROJECT_SECRET_KEY: lf_sk_1234567890
LANGFUSE_INIT_USER_EMAIL: ark@ark.com
LANGFUSE_INIT_USER_NAME: Ark Administrators
LANGFUSE_INIT_USER_PASSWORD: password123
```

### API Endpoints

**Langfuse API Base**: `http://langfuse-web.telemetry.svc.cluster.local:3000`

**Key Endpoints**:
```bash
# Create trace
POST /api/public/traces
Body: {
  "name": "agent-execution",
  "metadata": {},
  "userId": "user-123"
}

# Get trace
GET /api/public/traces/{id}

# Create generation
POST /api/public/generations
Body: {
  "trace_id": "...",
  "name": "llm-call",
  "model": "gpt-3.5-turbo",
  "input": {},
  "output": "...",
  "usage": {...}
}

# Submit score
POST /api/public/scores
Body: {
  "trace_id": "...",
  "name": "relevance",
  "value": 0.95,
  "comment": "High relevance"
}
```

## Summary

Langfuse provides comprehensive observability for ARK by:

1. **Capturing** all LLM interactions through traces
2. **Storing** events in high-performance ClickHouse
3. **Analyzing** performance, costs, and quality
4. **Integrating** with ARK Evaluator for RAGAS evaluation
5. **Presenting** insights through web dashboard

All components work together to provide a complete observability stack for LLM applications running on ARK.

