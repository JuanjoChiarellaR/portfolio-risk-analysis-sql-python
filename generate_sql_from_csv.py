"""
Portfolio Risk Analysis - Palo Alto Client
Generate SQL INSERT file from existing CSV files

Reads CSV files in /data/raw/ and generates pricing_inserts.sql
with INSERT statements for paloalto_client.fct_pricing_daily.

CSV format: date, adj_close (already pre-processed by download_data.py)
"""

import pandas as pd
import os
from datetime import datetime

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────

PORTFOLIO_TICKERS = ['IXN', 'QQQ', 'IEF', 'VNQ', 'GLD']
BENCHMARK_TICKERS = ['SPY', 'AGG', 'VT']
ALL_TICKERS       = PORTFOLIO_TICKERS + BENCHMARK_TICKERS

RAW_DATA_FOLDER = 'data/raw'
SQL_OUTPUT_FILE = 'data/pricing_inserts.sql'
SCHEMA          = 'paloalto_client'
TABLE           = 'fct_pricing_daily'


# ─────────────────────────────────────────────
# STEP 1 — Delete existing SQL file
# ─────────────────────────────────────────────

if os.path.exists(SQL_OUTPUT_FILE):
    os.remove(SQL_OUTPUT_FILE)
    print(f"Deleted existing file: {SQL_OUTPUT_FILE}")
else:
    print(f"No existing SQL file — will create new one")


# ─────────────────────────────────────────────
# STEP 2 — Read CSV files
# ─────────────────────────────────────────────

print(f"\nReading CSV files from {RAW_DATA_FOLDER}/...\n")

all_data       = {}
failed_tickers = []

for ticker in ALL_TICKERS:
    csv_path = os.path.join(RAW_DATA_FOLDER, f"{ticker}.csv")

    if not os.path.exists(csv_path):
        print(f"  {ticker}: CSV not found — skipped")
        failed_tickers.append(ticker)
        continue

    try:
        # CSV has columns: date, adj_close
        df = pd.read_csv(csv_path, parse_dates=['date'])
        df = df.dropna(subset=['adj_close'])
        df = df.sort_values('date')

        all_data[ticker] = df

        print(f"  {ticker}: {len(df)} rows | "
              f"{df['date'].min().date()} to {df['date'].max().date()} | "
              f"adj close: {df['adj_close'].min():.2f} - {df['adj_close'].max():.2f}")

    except Exception as e:
        print(f"  {ticker}: ERROR — {e}")
        failed_tickers.append(ticker)

print(f"\nRead complete. Success: {len(all_data)} | Failed: {len(failed_tickers)}")
if failed_tickers:
    print(f"Failed: {failed_tickers}")

if not all_data:
    print("\nNo data available. Cannot generate SQL file.")
    exit()


# ─────────────────────────────────────────────
# STEP 3 — Generate SQL INSERT file
# ─────────────────────────────────────────────

print(f"\nGenerating SQL file: {SQL_OUTPUT_FILE}...")

total_rows = 0

with open(SQL_OUTPUT_FILE, 'w') as f:

    f.write(f"-- ============================================================\n")
    f.write(f"-- Portfolio Risk Analysis - Palo Alto Client\n")
    f.write(f"-- INSERT statements for {SCHEMA}.{TABLE}\n")
    f.write(f"-- Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    f.write(f"-- Tickers: {', '.join(ALL_TICKERS)}\n")
    f.write(f"-- Price type: Adjusted Close only\n")
    f.write(f"-- Full OHLCV data available in /data/raw/ CSV files\n")
    f.write(f"-- ============================================================\n\n")
    f.write(f"USE {SCHEMA};\n\n")

    for ticker in ALL_TICKERS:
        if ticker not in all_data:
            f.write(f"-- WARNING: No data for {ticker} — skipped\n\n")
            continue

        df          = all_data[ticker]
        ticker_rows = 0

        f.write(f"-- {ticker}: {len(df)} rows (Adj Close only)\n")

        for _, row in df.iterrows():
            value    = round(float(row['adj_close']), 6)
            date_str = row['date'].strftime('%Y-%m-%d')
            f.write(f"INSERT INTO {SCHEMA}.{TABLE} (ticker, date, value) "
                    f"VALUES ('{ticker}', '{date_str}', {value:.6f});\n")
            ticker_rows += 1
            total_rows  += 1

        f.write(f"\n")
        print(f"  {ticker}: {ticker_rows} INSERT statements written")

    f.write(f"-- ============================================================\n")
    f.write(f"-- VALIDATION — run after loading to verify row counts\n")
    f.write(f"-- ============================================================\n")
    f.write(f"SELECT ticker, COUNT(*) AS rows, MIN(date) AS first_date, MAX(date) AS last_date\n")
    f.write(f"FROM {SCHEMA}.{TABLE}\n")
    f.write(f"GROUP BY ticker\n")
    f.write(f"ORDER BY ticker;\n")

print(f"\nSQL file ready: {SQL_OUTPUT_FILE}")
print(f"Total INSERT statements: {total_rows}")
print(f"\nNext step: run script1.sql in MySQL Workbench, then load {SQL_OUTPUT_FILE}")
