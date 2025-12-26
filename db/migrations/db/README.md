# Database

This project uses Postgres.

## Apply migration

Run `001_init.sql` using any Postgres client:

- psql:
  psql "$DATABASE_URL" -f db/migrations/001_init.sql

Tables are created under the `invest` schema:
- invest.funds
- invest.fund_nav_history
- invest.fund_returns
- invest.pipeline_runs

Convenience view:
- invest.v_latest_30d_returns
