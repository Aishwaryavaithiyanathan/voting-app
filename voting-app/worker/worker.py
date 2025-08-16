import os
import time
import redis
import psycopg2

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
DB_HOST = os.getenv("DB_HOST", "db")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("POSTGRES_DB", "voting")
DB_USER = os.getenv("POSTGRES_USER", "postgres")
DB_PASS = os.getenv("POSTGRES_PASSWORD", None)
DB_PASS_FILE = os.getenv("POSTGRES_PASSWORD_FILE")

if DB_PASS is None and DB_PASS_FILE and os.path.exists(DB_PASS_FILE):
    with open(DB_PASS_FILE) as f:
        DB_PASS = f.read().strip()

r = redis.Redis(host=REDIS_HOST, port=6379, db=0)

def get_conn():
    while True:
        try:
            return psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASS)
        except Exception as e:
            print("Waiting for database...", e)
            time.sleep(2)

def ensure_table(conn):
    with conn.cursor() as cur:
        cur.execute("""
        CREATE TABLE IF NOT EXISTS votes (
            option TEXT PRIMARY KEY,
            count  INTEGER NOT NULL DEFAULT 0
        );
        """)
        conn.commit()


def increment_vote(conn, choice):
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO votes(option, count) VALUES (%s, 1)
            ON CONFLICT(option) DO UPDATE SET count = votes.count + 1
            """,
            (choice,)
        )
        conn.commit()


def main():
    conn = get_conn()
    ensure_table(conn)
    print("Worker started; waiting for votes...")
    while True:
        try:
            _, val = r.brpop("votes")  # blocking pop
            choice = val.decode("utf-8")
            if choice in ("cats", "dogs"):
                increment_vote(conn, choice)
                print(f"counted: {choice}")
        except Exception as e:
            print("Error processing vote:", e)
            time.sleep(1)

if __name__ == "__main__":
    main()
