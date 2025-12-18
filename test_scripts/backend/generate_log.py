import logging
import random

import ecs_logging
from faker import Faker
from tqdm import tqdm

fake = Faker()

# Config
NUM_LOGS = 100_000  # adjust as needed
LOG_FILE = "./logs/mock_logs2.json"

# Example FastAPI endpoints
endpoints = [
    "/api/v1/users",
    "/api/v1/orders",
    "/api/v1/products",
    "/api/v1/cart",
    "/health",
]

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

# Set up ECS logger
logger = logging.getLogger("app")
logger.setLevel(logging.DEBUG)


def setup_logger():
    """Configure logger with ECS formatter writing to file"""
    handler = logging.FileHandler(LOG_FILE, mode="w")
    handler.setFormatter(ecs_logging.StdlibFormatter())
    logger.addHandler(handler)


def generate_fastapi_log():
    ip = fake.ipv4()
    method = random.choice(methods)
    endpoint = random.choice(endpoints)
    status = random.choices(
        [200, 201, 400, 401, 403, 404, 500], weights=[60, 10, 5, 5, 5, 10, 5]
    )[0]
    response_time = round(random.uniform(0.01, 1.5), 3)
    ts = fake.date_time_between(start_date="-30d", end_date="now")

    extra = {
        "log.type": "fastapi",
        "client.ip": ip,
        "http.request.method": method,
        "url.path": endpoint,
        "http.response.status_code": status,
        "event.duration": response_time * 1_000_000_000,  # convert to nanoseconds
    }

    # Choose log level based on status code and response time
    if status >= 500:
        logger.error(
            f"FastAPI request failed {method} {endpoint} - Status {status}", extra=extra
        )
    elif status >= 400:
        logger.warning(
            f"FastAPI client error {method} {endpoint} - Status {status}", extra=extra
        )
    elif response_time > 1.0:
        logger.warning(
            f"FastAPI slow request {method} {endpoint} - {response_time}s", extra=extra
        )
    elif endpoint == "/health":
        logger.debug(f"FastAPI health check {method} {endpoint}", extra=extra)
    else:
        logger.info(f"FastAPI request {method} {endpoint}", extra=extra)


def generate_postgres_log():
    ts = fake.date_time_between(start_date="-30d", end_date="now")
    user_id = random.randint(1, 1000)
    value = random.randint(1, 100)
    query_template = random.choice(queries)
    query = query_template.format(user_id, value)
    duration = round(random.uniform(1, 500), 2)  # ms

    extra = {
        "log.type": "postgres",
        "user.name": f"user_{user_id}",
        "db.statement": query,
        "event.duration": duration * 1_000_000,  # convert ms to nanoseconds
    }

    # Choose log level based on duration and query type
    if duration > 400:
        logger.error(f"PostgreSQL query timeout - {duration}ms", extra=extra)
    elif duration > 200:
        logger.warning(f"PostgreSQL slow query - {duration}ms", extra=extra)
    elif "SELECT" in query:
        logger.debug("PostgreSQL query executed", extra=extra)
    else:
        logger.info("PostgreSQL query executed", extra=extra)


def generate_redis_log():
    ts = fake.date_time_between(start_date="-30d", end_date="now")
    action = random.choice(redis_actions)
    key = f"cache:{random.randint(1, 1000)}"
    duration = round(random.uniform(0.1, 50), 2)  # ms

    extra = {
        "log.type": "redis",
        "redis.action": action,
        "redis.key": key,
        "event.duration": duration * 1_000_000,  # convert ms to nanoseconds
    }

    # Choose log level based on duration and action
    if duration > 40:
        logger.error(f"Redis {action} operation failed - {duration}ms", extra=extra)
    elif duration > 20:
        logger.warning(f"Redis {action} operation slow - {duration}ms", extra=extra)
    elif action == "DEL":
        logger.info(f"Redis {action} operation", extra=extra)
    else:
        logger.debug(f"Redis {action} operation", extra=extra)


def main():
    setup_logger()

    for _ in tqdm(range(NUM_LOGS)):
        log_type = random.choices(
            ["fastapi", "postgres", "redis"], weights=[50, 30, 20]
        )[0]
        if log_type == "fastapi":
            generate_fastapi_log()
        elif log_type == "postgres":
            generate_postgres_log()
        else:
            generate_redis_log()

    print(f"✅ Generated {NUM_LOGS} logs in {LOG_FILE}")


if __name__ == "__main__":
    main()
