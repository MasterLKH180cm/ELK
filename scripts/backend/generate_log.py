import random
import datetime
import json
from faker import Faker
from tqdm import tqdm

fake = Faker()

# Config
NUM_LOGS = 100_000  # adjust as needed
LOG_FILE = "./logs/mock_logs2.json"

# Example FastAPI endpoints
endpoints = ["/api/v1/users", "/api/v1/orders", "/api/v1/products", "/api/v1/cart", "/health"]

# Example HTTP methods
methods = ["GET", "POST", "PUT", "DELETE"]

# PostgreSQL queries
queries = [
    "SELECT * FROM users WHERE id = {};",
    "INSERT INTO orders (user_id, total) VALUES ({}, {});",
    "UPDATE products SET stock = stock - {} WHERE id = {};",
    "DELETE FROM cart WHERE user_id = {};",
]

# Redis actions
redis_actions = ["GET", "SET", "DEL", "EXPIRE"]

def generate_fastapi_log():
    ip = fake.ipv4()
    method = random.choice(methods)
    endpoint = random.choice(endpoints)
    status = random.choices([200, 201, 400, 401, 403, 404, 500], weights=[60,10,5,5,5,10,5])[0]
    response_time = round(random.uniform(0.01, 1.5), 3)
    ts = fake.date_time_between(start_date='-30d', end_date='now')
    return {
        "type": "fastapi",
        "timestamp": ts.isoformat(),
        "ip": ip,
        "method": method,
        "endpoint": endpoint,
        "status": status,
        "response_time": response_time
    }

def generate_postgres_log():
    ts = fake.date_time_between(start_date='-30d', end_date='now')
    user_id = random.randint(1, 1000)
    value = random.randint(1, 100)
    query_template = random.choice(queries)
    query = query_template.format(user_id, value)
    duration = round(random.uniform(1, 500), 2)  # ms
    return {
        "type": "postgres",
        "timestamp": ts.isoformat(),
        "user": f"user_{user_id}",
        "query": query,
        "duration_ms": duration
    }

def generate_redis_log():
    ts = fake.date_time_between(start_date='-30d', end_date='now')
    action = random.choice(redis_actions)
    key = f"cache:{random.randint(1,1000)}"
    duration = round(random.uniform(0.1, 50), 2)  # ms
    return {
        "type": "redis",
        "timestamp": ts.isoformat(),
        "action": action,
        "key": key,
        "duration_ms": duration
    }

def main():
    with open(LOG_FILE, "w") as f:
        for _ in tqdm(range(NUM_LOGS)):
            log_type = random.choices(["fastapi","postgres","redis"], weights=[50,30,20])[0]
            if log_type == "fastapi":
                log = generate_fastapi_log()
            elif log_type == "postgres":
                log = generate_postgres_log()
            else:
                log = generate_redis_log()
            f.write(json.dumps(log) + "\n")
    print(f"✅ Generated {NUM_LOGS} logs in {LOG_FILE}")

if __name__ == "__main__":
    main()
