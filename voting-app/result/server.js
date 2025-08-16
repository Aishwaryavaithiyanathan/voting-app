const express = require('express');
const { Pool } = require('pg');

const app = express();
const PORT = 80;

const cfg = {
  host: process.env.DB_HOST || 'db',
  port: +(process.env.DB_PORT || 5432),
  user: process.env.POSTGRES_USER || 'postgres',
  password: process.env.POSTGRES_PASSWORD,
  database: process.env.POSTGRES_DB || 'voting'
};

if (!cfg.password && process.env.POSTGRES_PASSWORD_FILE) {
  const fs = require('fs');
  try { cfg.password = fs.readFileSync(process.env.POSTGRES_PASSWORD_FILE, 'utf8').trim(); } catch {}
}

const pool = new Pool(cfg);

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok' });
  } catch (e) {
    res.status(500).json({ status: 'error', detail: String(e) });
  }
});

app.get('/', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT option, count FROM votes ORDER BY option');
    const counts = Object.fromEntries(rows.map(r => [r.option, r.count]));
    const cats = counts.cats || 0;
    const dogs = counts.dogs || 0;
    res.send(`<!doctype html><title>Results</title>
      <h1>Results</h1>
      <p>Cats: <b>${cats}</b></p>
      <p>Dogs: <b>${dogs}</b></p>
      <p><a href="/health">health</a></p>`);
  } catch (e) {
    res.status(500).send('DB error: ' + String(e));
  }
});

app.listen(PORT, () => console.log(`Result UI on :${PORT}`));
