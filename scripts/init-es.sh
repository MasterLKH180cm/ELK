#!/bin/bash

# Elasticsearch 初始化腳本 - 在容器啟動時執行
# 用於設置索引模板和 ILM 政策

set -e

ES_HOST="http://elasticsearch:9200"
MAX_ATTEMPTS=30
ATTEMPT=0

echo "⏳ 等待 Elasticsearch 就緒..."

# 等待 Elasticsearch 啟動
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s -f "$ES_HOST/_cluster/health" > /dev/null 2>&1; then
        echo "✅ Elasticsearch 已就緒"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "⏳ 嘗試 $ATTEMPT/$MAX_ATTEMPTS... 等待中"
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "❌ Elasticsearch 啟動超時"
    exit 1
fi

echo ""
echo "🔧 設置 Elasticsearch 索引和 ILM 政策..."
echo ""

# ===== 建立 ILM 政策 =====

create_ilm_policy() {
    local POLICY_NAME=$1
    local HOT_DAYS=${2:-30}
    local DELETE_DAYS=${3:-90}

    echo "📌 建立 ILM 政策: $POLICY_NAME"

    curl -s -X PUT "$ES_HOST/_ilm/policy/$POLICY_NAME" \
        -H "Content-Type: application/json" \
        -d "{
  \"policy\": \"$POLICY_NAME\",
  \"phases\": {
    \"hot\": {
      \"min_age\": \"0d\",
      \"actions\": {
        \"rollover\": {
          \"max_primary_store_size\": \"50GB\",
          \"max_age\": \"1d\"
        },
        \"set_priority\": {
          \"priority\": 100
        }
      }
    },
    \"warm\": {
      \"min_age\": \"${HOT_DAYS}d\",
      \"actions\": {
        \"set_priority\": {
          \"priority\": 50
        }
      }
    },
    \"cold\": {
      \"min_age\": \"$((DELETE_DAYS - 30))d\",
      \"actions\": {
        \"set_priority\": {
          \"priority\": 0
        }
      }
    },
    \"delete\": {
      \"min_age\": \"${DELETE_DAYS}d\",
      \"actions\": {
        \"delete\": {}
      }
    }
  }
}"

    echo "  ✅ 已建立"
}

# ===== 建立通用映射元件 =====

echo "📌 建立通用映射元件"

curl -s -X PUT "$ES_HOST/_component_template/logs-mapping" \
    -H "Content-Type: application/json" \
    -d '{
  "template": {
    "mappings": {
      "dynamic": true,
      "dynamic_templates": [
        {
          "strings_as_keywords": {
            "match_mapping_type": "string",
            "mapping": {
              "type": "keyword"
            }
          }
        }
      ]
    }
  }
}'

echo "  ✅ 已建立"

# ===== 建立索引模板 =====

create_index_template() {
    local TEMPLATE_NAME=$1
    local INDEX_PATTERN=$2
    local ILM_POLICY=$3

    echo "📌 建立索引模板: $TEMPLATE_NAME (pattern: $INDEX_PATTERN)"

    curl -s -X PUT "$ES_HOST/_index_template/$TEMPLATE_NAME" \
        -H "Content-Type: application/json" \
        -d "{
  \"index_patterns\": [\"$INDEX_PATTERN\"],
  \"composed_of\": [\"logs-mapping\"],
  \"priority\": 100,
  \"template\": {
    \"settings\": {
      \"number_of_shards\": 1,
      \"number_of_replicas\": 0,
      \"index.lifecycle.name\": \"$ILM_POLICY\",
      \"index.mapping.total_fields.limit\": 2000
    },
    \"mappings\": {
      \"properties\": {
        \"@timestamp\": { \"type\": \"date\" },
        \"service.name\": { \"type\": \"keyword\" },
        \"service.namespace\": { \"type\": \"keyword\" },
        \"deployment.environment\": { \"type\": \"keyword\" },
        \"log.level\": { \"type\": \"keyword\" },
        \"event.domain\": { \"type\": \"keyword\" },
        \"event.type\": { \"type\": \"keyword\" },
        \"event.category\": { \"type\": \"keyword\" },
        \"event.duration_ms\": { \"type\": \"double\" },
        \"event.outcome\": { \"type\": \"keyword\" },
        \"trace.id\": { \"type\": \"keyword\" },
        \"span.id\": { \"type\": \"keyword\" },
        \"user.id\": { \"type\": \"keyword\" },
        \"session.id\": { \"type\": \"keyword\" },
        \"http.method\": { \"type\": \"keyword\" },
        \"http.status_code\": { \"type\": \"integer\" },
        \"http.path\": { \"type\": \"text\" },
        \"client.ip\": { \"type\": \"ip\" },
        \"error.type\": { \"type\": \"keyword\" },
        \"error.message\": { \"type\": \"text\" },
        \"message\": { \"type\": \"text\" }
      }
    }
  }
}"

    echo "  ✅ 已建立"
}

# ===== 執行設置 =====

echo ""

# 建立 ILM 政策
create_ilm_policy "logs-retention-30-90" 30 90
create_ilm_policy "logs-retention-7-30" 7 30

echo ""

# 建立索引模板
create_index_template "logs-auth" "logs-auth-*" "logs-retention-30-90"
create_index_template "logs-frontend" "logs-frontend-*" "logs-retention-7-30"
create_index_template "logs-backend" "logs-backend-*" "logs-retention-30-90"
create_index_template "logs-security" "logs-security-*" "logs-retention-30-90"

echo ""
echo "✅ Elasticsearch 索引和 ILM 政策設置完成！"
echo ""
