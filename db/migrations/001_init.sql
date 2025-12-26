-- 001_init.sql
-- Core schema for DR Investment Fund NAV tracking + 30D annualized returns

BEGIN;

-- Optional: keep everything in its own schema
CREATE SCHEMA IF NOT EXISTS invest;

-- ---------- FUNDS (registry / config mirror) ----------
CREATE TABLE IF NOT EXISTS invest.funds (
  fund_id            TEXT PRIMARY KEY, -- slug, stable identifier, e.g. 'bhd_liquidez_usd'
  fund_name          TEXT NOT NULL,
  manager            TEXT NOT NULL,     -- AFI/SAFI name
  currency           TEXT NOT NULL CHECK (currency IN ('DOP','USD')),
  category           TEXT,              -- optional: money_market, income, etc.

  source_type        TEXT NOT NULL CHECK (source_type IN ('historical_pdf','daily_pdf','html_table','api')),
  source_url         TEXT NOT NULL,
  parser_profile     TEXT,              -- e.g. 'historical_table_v1' (used by extractor)
  is_active          BOOLEAN NOT NULL DEFAULT TRUE,

  notes              TEXT,

  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Small helper index for active funds listing
CREATE INDEX IF NOT EXISTS idx_funds_active ON invest.funds (is_active);

-- ---------- NAV HISTORY (source of truth) ----------
CREATE TABLE IF NOT EXISTS invest.fund_nav_history (
  fund_id            TEXT NOT NULL REFERENCES invest.funds(fund_id) ON DELETE CASCADE,
  valuation_date     DATE NOT NULL,
  nav_per_share      NUMERIC(20,10) NOT NULL CHECK (nav_per_share > 0),

  source_url         TEXT NOT NULL,
  fetched_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  raw_hash           TEXT, -- hash of file/page content used

  PRIMARY KEY (fund_id, valuation_date)
);

-- Helpful indexes for time-window queries
CREATE INDEX IF NOT EXISTS idx_nav_history_date ON invest.fund_nav_history (valuation_date);
CREATE INDEX IF NOT EXISTS idx_nav_history_fund_date_desc ON invest.fund_nav_history (fund_id, valuation_date DESC);

-- ---------- RETURNS (derived) ----------
CREATE TABLE IF NOT EXISTS invest.fund_returns (
  fund_id            TEXT NOT NULL REFERENCES invest.funds(fund_id) ON DELETE CASCADE,
  as_of_date         DATE NOT NULL,
  window_days        INTEGER NOT NULL CHECK (window_days > 0),

  start_date_used    DATE NOT NULL,
  end_date_used      DATE NOT NULL,

  nav_start          NUMERIC(20,10) NOT NULL CHECK (nav_start > 0),
  nav_end            NUMERIC(20,10) NOT NULL CHECK (nav_end > 0),

  total_return       NUMERIC(20,10) NOT NULL,   -- e.g. 0.0123 = 1.23%
  annualized_return  NUMERIC(20,10) NOT NULL,

  method_note        TEXT, -- e.g. "Start date stepped back to previous available valuation date."

  computed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (fund_id, as_of_date, window_days)
);

CREATE INDEX IF NOT EXISTS idx_returns_asof ON invest.fund_returns (as_of_date DESC);
CREATE INDEX IF NOT EXISTS idx_returns_fund_asof ON invest.fund_returns (fund_id, as_of_date DESC);

-- ---------- PIPELINE RUNS (audit/logging) ----------
CREATE TABLE IF NOT EXISTS invest.pipeline_runs (
  run_id             BIGSERIAL PRIMARY KEY,
  workflow_name      TEXT NOT NULL,  -- e.g. 'daily_ingestion', 'daily_returns'
  started_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at        TIMESTAMPTZ,
  status             TEXT NOT NULL CHECK (status IN ('ok','warning','failed')),

  funds_processed    INTEGER NOT NULL DEFAULT 0,
  records_inserted   INTEGER NOT NULL DEFAULT 0,
  records_updated    INTEGER NOT NULL DEFAULT 0,

  errors_json        JSONB, -- store structured errors/tracebacks
  run_version        TEXT   -- e.g. git commit hash or 'v0.1'
);

CREATE INDEX IF NOT EXISTS idx_pipeline_runs_started ON invest.pipeline_runs (started_at DESC);

-- ---------- Optional convenience view: latest 30D annualized per fund ----------
CREATE OR REPLACE VIEW invest.v_latest_30d_returns AS
SELECT DISTINCT ON (r.fund_id)
  r.fund_id,
  f.fund_name,
  f.manager,
  f.currency,
  r.as_of_date,
  r.start_date_used,
  r.end_date_used,
  r.total_return,
  r.annualized_return,
  r.computed_at
FROM invest.fund_returns r
JOIN invest.funds f ON f.fund_id = r.fund_id
WHERE r.window_days = 30
ORDER BY r.fund_id, r.as_of_date DESC;

COMMIT;
