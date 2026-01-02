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

    echo "📌 檢查 ILM 政策: $POLICY_NAME"

    # Check if policy exists
    EXISTING=$(curl -s "$ES_HOST/_ilm/policy/$POLICY_NAME" 2>/dev/null)
    
    if echo "$EXISTING" | grep -q "$POLICY_NAME"; then
        # Extract existing config
        EXISTING_HOT=$(echo "$EXISTING" | grep -o '"warm":{"min_age":"[0-9]*d"' | grep -o '[0-9]*' || echo "")
        EXISTING_DELETE=$(echo "$EXISTING" | grep -o '"delete":{"min_age":"[0-9]*d"' | grep -o '[0-9]*' || echo "")
        
        if [ "$EXISTING_HOT" = "$HOT_DAYS" ] && [ "$EXISTING_DELETE" = "$DELETE_DAYS" ]; then
            echo "  ⏭️  已存在相同設定，跳過"
            return 0
        else
            echo "  🔄 設定不同，更新中..."
        fi
    fi

    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$ES_HOST/_ilm/policy/$POLICY_NAME" \
        -H "Content-Type: application/json" \
        -d "{
  \"policy\": {
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
  }
}")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "  ✅ 已建立/更新"
    else
        echo "  ❌ 失敗 (HTTP $HTTP_CODE)"
        echo "$RESPONSE"
    fi
}

# ===== 建立通用映射元件 =====

echo "📌 檢查通用映射元件"

# Check if component template exists
EXISTING=$(curl -s "$ES_HOST/_component_template/logs-mapping" 2>/dev/null)

if echo "$EXISTING" | grep -q '"logs-mapping"' && echo "$EXISTING" | grep -q '"strings_as_keywords"'; then
    echo "  ⏭️  已存在相同設定，跳過"
else
    if echo "$EXISTING" | grep -q '"logs-mapping"'; then
        echo "  🔄 設定不同，更新中..."
    fi
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$ES_HOST/_component_template/logs-mapping" \
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
}')

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    if [ "$HTTP_CODE" = "200" ]; then
        echo "  ✅ 已建立/更新"
    else
        echo "  ❌ 失敗 (HTTP $HTTP_CODE)"
        echo "$RESPONSE"
    fi
fi

# ===== 建立索引模板 =====

create_index_template() {
    local TEMPLATE_NAME=$1
    local INDEX_PATTERN=$2
    local ILM_POLICY=$3

    echo "📌 檢查索引模板: $TEMPLATE_NAME (pattern: $INDEX_PATTERN)"

    # Check if index template exists with same config
    EXISTING=$(curl -s "$ES_HOST/_index_template/$TEMPLATE_NAME" 2>/dev/null)
    
    if echo "$EXISTING" | grep -q "$TEMPLATE_NAME"; then
        EXISTING_PATTERN=$(echo "$EXISTING" | grep -o "\"index_patterns\":\[\"[^\"]*\"\]" || echo "")
        EXISTING_ILM=$(echo "$EXISTING" | grep -o "\"index.lifecycle.name\":\"[^\"]*\"" || echo "")
        
        if echo "$EXISTING_PATTERN" | grep -q "$INDEX_PATTERN" && echo "$EXISTING_ILM" | grep -q "$ILM_POLICY"; then
            echo "  ⏭️  已存在相同設定，跳過"
            return 0
        else
            echo "  🔄 設定不同，更新中..."
        fi
    fi

    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$ES_HOST/_index_template/$TEMPLATE_NAME" \
        -H "Content-Type: application/json" \
        -d "{
  \"index_patterns\": [\"$INDEX_PATTERN\"],
  \"data_stream\": { },
  \"composed_of\": [\"logs-mapping\"],
  \"priority\": 200,
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
    )

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    if [ "$HTTP_CODE" = "200" ]; then
        echo "  ✅ 已建立"
    else
        echo "  ❌ 失敗 (HTTP $HTTP_CODE)"
        echo "$RESPONSE"
    fi
}

# ===== 建立資料流 =====

create_data_stream() {
    local DATA_STREAM_NAME=$1

    echo "📌 檢查資料流: $DATA_STREAM_NAME"

    # Check if data stream already exists
    EXISTING=$(curl -s "$ES_HOST/_data_stream/$DATA_STREAM_NAME" 2>/dev/null)
    
    if echo "$EXISTING" | grep -q "$DATA_STREAM_NAME"; then
        echo "  ⏭️  已存在，跳過"
        return 0
    fi

    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$ES_HOST/_data_stream/$DATA_STREAM_NAME" \
        -H "Content-Type: application/json")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        echo "  ✅ 已建立"
    else
        echo "  ⚠️  回應 (HTTP $HTTP_CODE)"
        echo "$RESPONSE"
    fi
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
create_index_template "logs-ohif" "logs-ohif-*" "logs-retention-30-90"
create_index_template "logs-dictation_backend" "logs-dictation_backend-*" "logs-retention-30-90"
create_index_template "logs-dictation_frontend" "logs-dictation_frontend-*" "logs-retention-7-30"
create_index_template "logs-trace" "logs-trace-*" "logs-retention-30-90"
create_index_template "logs-metrics" "logs-metrics-*" "logs-retention-7-30"
create_index_template "logs-session" "logs-session-*" "logs-retention-30-90"
create_index_template "logs-worklist" "logs-worklist-*" "logs-retention-30-90"
create_index_template "logs-viewer" "logs-viewer-*" "logs-retention-30-90"
create_index_template "logs-default" "logs-default-*" "logs-retention-30-90"

echo ""

# Note: Data streams are auto-created by Elasticsearch when Logstash sends data
# No need to pre-create them - they will be created automatically using the index templates
# Format: logs-{dataset}-default (where dataset comes from event_domain)

echo ""
echo "✅ Elasticsearch 索引模板和 ILM 政策設置完成！"
echo "   資料流將在首次接收資料時自動建立"
echo ""