# **Centralized Logging & Product Analytics Comprehensive Guide (PostHog / ClickHouse Separated)**

---

## **TL;DR**

It is recommended to discuss with Brian the logging strategy divided into two categories:

a. **Pure UI interaction logs**

* Examples: user clicks, page views, form actions
* Suitable for product analytics, sent to PostHog / posthog-js

b. **Backend interaction logs**

* Examples: API calls, errors, exceptions, server responses
* Discuss which logs to persist, how to store them, and priority
* Suitable to send to OTel Collector → Kafka → Elasticsearch / ClickHouse pipeline

> **Key point**: Observability and product analytics should be separated; avoid using the same tools for both purposes.

---

## **Part 1: Current Architecture**

```
Log Sources
 ├─ Browser → FastAPI / OTel Web SDK
 ├─ VM + Docker → Fluent Bit
 └─ Serverless → Cloud Log Service → Log Sink / Subscription
             │
             ▼
        OpenTelemetry Collector
             │
             ▼
        Kafka (Zookeeper)
             │
             ▼
          Logstash
             │
             ▼
        Elasticsearch
             │
             ▼
            Kibana
```

### **Architecture Explanation**

1. **Browser**

   * Uses FastAPI backend + OTel Web SDK to collect frontend events and errors.
   * Events are sent as traces / spans / logs to the OTel Collector.

2. **VM + Docker**

   * Fluent Bit collects container logs and system logs.
   * Structured logs are sent to the OTel Collector.

3. **Serverless**

   * Cloud log service (e.g., Cloud Logging, CloudWatch, Application Insights).
   * Logs are routed via Log Sink / Subscription to the OTel Collector.

4. **OpenTelemetry Collector**

   * Unified collection of logs / traces / metrics from all sources.
   * Supports forwarding to Kafka or other downstream systems.
   * Can perform sampling, normalization, and additional processing.

5. **Kafka**

   * Acts as an event/log buffer and fan-out layer.
   * Supports multiple downstream consumers.

6. **Logstash**

   * Processes and transforms logs with multiple input/output formats.
   * Supports field filtering, parsing, and structuring.

7. **Elasticsearch + Kibana**

   * Elasticsearch stores structured logs.
   * Kibana provides search, visualization, and monitoring.

---

## **Part 2: PostHog**

PostHog is a **self-hosted product analytics platform** designed for capturing and analyzing user behavior. According to DeepWiki, it follows a **polyglot microservices architecture** optimized for high-throughput ingestion and complex analytics.

### **Detailed System Architecture (DeepWiki)**

PostHog's architecture is divided into distinct planes for ingestion, processing, storage, and querying:

#### **1. Ingestion Layer (High Throughput)**
* **Capture Service (Rust)**: Handles high-volume event ingestion at the edge.
  * Validates/preprocesses events.
  * Writes to the `events_plugin_ingestion` Kafka topic.
* **Replay Capture (Rust)**: Handles session recording snapshots.
  * Writes to `session_recording_events` Kafka topic.
* **Benefit**: Separating ingestion (Rust) from processing ensures low latency and reliability under load.

#### **2. Event Processing (Plugin Server)**
* **Plugin Server (Node.js)**: Consumes events from Kafka.
  * **Transformation**: Uses `HogTransformerService` for event modification.
  * **Enrichment**: Property extraction and CDP routing (`CdpProcessedEventsConsumer`).
  * **Writing**: Writes processed events to ClickHouse.
  * **Modes**: Operates in different modes like `ingestion_v2` (main pipeline) and `cdp_cyclotron_worker` (background jobs).

#### **3. Storage Architecture**
PostHog uses a hybrid storage model:
* **ClickHouse (Analytics)**: Stores high-volume event data (`events`, `sessions`, `persons`, `groups`). Optimized for OLAP queries.
* **PostgreSQL (App State)**: Stores relational data like user accounts, feature flags, dashboard definitions, and survey configs.
* **Redis**: Handles caching, rate limiting, and Celery task queues.
* **S3/MinIO**: Object storage for session recording blobs and data exports.

#### **4. Query & API Layer**
* **Django API**: Handles auth, metadata, and business logic.
* **HogQL**: A proprietary SQL dialect that creates a **Query Abstraction Layer**.
  * Translates analytics requests into optimized ClickHouse SQL.
  * Ensures type safety via a unified `QuerySchema` (TypeScript/Python).

#### **5. Background Jobs**
* **Celery**: Handles short async tasks (<30s) like emails and cache invalidation.
* **Temporal**: Manages long-running workflows (minutes/hours) such as data imports/exports and batch processing.

### **Use Cases**

* **Product Analytics**: Funnels, cohorts, retention, feature usage.
* **Session Replay**: Visual playback of user interactions (stored in S3/MinIO).
* **Feature Management**: Feature flags and A/B testing (state in Postgres).

### **Pros**

* **Purpose-Built Architecture**: Rust for speed, ClickHouse for analytics speed, Postgres for reliability.
* **Data Control**: Self-hosted allows full control over privacy and retention.
* **Resilience**: Kafka decoupling prevents data loss during spikes.

### **Cons**

* **Complexity**: Managing ClickHouse, Kafka, Zookeeper, and Temporal requires DevOps effort.
* **Scope**: strictly for *product* data; not a replacement for system observability.

### **PostHog Plane Architecture**

```
Browser/SDK
  │
  ▼
Capture Service (Rust)
  │
  ▼
Kafka
  │
  ▼
Plugin Server (Node) ──────────┐
  │              │             │
  ▼              ▼             ▼
ClickHouse    Postgres     S3/MinIO
(Analytics)   (App State)  (Recordings)
```

> **Note**: This ClickHouse cluster is **internal** to PostHog and should generally remain separate from the centralized logging ClickHouse to avoid resource contention and schema conflicts.

---

## **Part 3: ClickHouse**

ClickHouse is a **columnar, distributed OLAP database** suitable for high-throughput events/log storage and analysis.

### **Use Cases**

* Long-term log storage
* Aggregation queries (e.g., daily API usage, error counts)
* SQL-based analysis

### **Key Features**

* High write and query performance at low cost
* Ideal for long-term historical log storage
* Supports complex aggregation and time-series analysis
* Not suitable for full-text search

---

## **Part 4: ClickHouse Deployment Analysis**

### **Pros**

* High-throughput writes and aggregation queries
* Works with Kafka fan-out to prevent data loss
* Suitable for long-term event tracking and historical analysis

### **Cons**

* Not ideal for real-time full-text search or debugging
* Requires predefined schema; dynamic log mapping weaker than Elasticsearch
* Engineering team must maintain SQL queries and understand ClickHouse

### **ClickHouse Plane Architecture (Updated)**

```
Log Sources
 ├─ Browser → OTel Web SDK
 ├─ VM + Docker → Fluent Bit
 └─ Serverless → Cloud Log Service → Log Sink / Subscription
             │
             ▼
        OpenTelemetry Collector
             │
             ▼
             Kafka
            /    \
           /      \
      Elasticsearch  ClickHouse
           │           │
        Kibana     Analytics / Aggregation
```

### **Explanation**

1. **Browser / VM / Serverless**

   * All log sources go to OTel Collector.

2. **OTel Collector → Kafka**

   * Kafka fans out logs to both Elasticsearch and ClickHouse.

3. **ClickHouse**

   * Stores long-term logs for analytics and aggregation
   * Supports SQL queries, independent of Elasticsearch

4. **Elasticsearch**

   * Retains short-term debug / hot logs
   * Kibana used for real-time monitoring and search

---

## **Part 5: Logstash Role and Impact of Removal**

### **Functions**

* Parse / structure logs
* Filter / merge multi-source logs
* Format conversion

### **Impact of Removing Logstash**

* **Advantages**

  * Reduces CPU load and single-point bottleneck
  * Simplifies architecture and lowers maintenance costs

* **Disadvantages**

  * Parsing / structuring must move to Fluent Bit / OTel Collector / Kafka consumer
  * No automatic format conversion; requires engineering maintenance

> In a modern Kafka + OTel Collector setup, Logstash can be removed if parsing and filtering are handled elsewhere.

---

## **Summary Recommendations**

1. **PostHog**

   * Focused on frontend product events
   * Separate from observability pipeline

2. **ClickHouse**

   * Suitable for long-term log storage and aggregation
   * Works with Kafka fan-out
   * Elasticsearch reserved for short-term debug / hot logs

3. **Logstash**

   * Can be removed
   * Ensure parsing / filtering / structuring is handled by other components

4. **Overall Layered Architecture**

```
Observability Plane:
Browser / VM / Serverless → OTel Collector → Kafka → Elasticsearch (hot logs) → Kibana

Analytics Plane:
Browser → posthog-js → PostHog Server → Event Storage (PostHog ClickHouse)

ClickHouse Plane:
Browser / VM / Serverless → OTel Collector → Kafka → ClickHouse → Analytics / Aggregation
```

> Clear separation of responsibilities:
>
> * Observability: SRE / Engineering
> * Product Analytics: Product / Growth
