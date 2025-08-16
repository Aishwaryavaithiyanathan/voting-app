from flask import Flask, render_template_string, request, redirect
import os
import redis

app = Flask(__name__)
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
r = redis.Redis(host=REDIS_HOST, port=6379, db=0)

tpl = """
<!doctype html>
<title>Voting App</title>
<h1>Cast your vote</h1>
<form method="post" action="/vote">
  <button name="vote" value="cats">Cats</button>
  <button name="vote" value="dogs">Dogs</button>
</form>
<p><a href="/health">health</a> | <a href="/">home</a></p>
"""

@app.get("/")
def index():
    return render_template_string(tpl)

@app.get("/health")
def health():
    try:
        r.ping()
        return {"status": "ok"}
    except Exception as e:
        return {"status": "error", "detail": str(e)}, 500

@app.post("/vote")
def vote():
    v = request.form.get("vote")
    if v not in ("cats", "dogs"):
        return redirect("/")
    r.lpush("votes", v)
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
