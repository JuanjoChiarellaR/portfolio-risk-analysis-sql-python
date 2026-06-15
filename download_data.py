"""
Portfolio Risk Analysis - Palo Alto Client
Data Download Script

Downloads daily OHLCV data for all tickers from Yahoo Finance.
CSV files save full OHLCV. SQL inserts use only Adj Close.

Portfolio tickers:  IXN, QQQ, IEF, VNQ, GLD
Benchmark tickers:  SPY, AGG, VT
Date range: January 1 2024 to June 13 2026
"""

import yfinance as yf
import pandas as pd
import os
import time
from datetime import datetime

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────

PORTFOLIO_TICKERS = ['IXN', 'QQQ', 'IEF', 'VNQ', 'GLD']
BENCHMARK_TICKERS = ['SPY', 'AGG', 'VT']
ALL_TICKERS       = PORTFOLIO_TICKERS + BENCHMARK_TICKERS

START_DATE      = '2024-01-01'
END_DATE        = '2026-06-13'
RAW_DATA_FOLDER = 'data/raw'
SQL_OUTPUT_FILE = 'data/pricing_inserts.sql'
SCHEMA          = 'paloalto_client'
TABLE           = 'fct_pricing_daily'

# Delay between downloads to avoid rate limiting
DELAY_SECONDS = 3

# Number of retries per ticker if rate limited
MAX_RETRIES = 3


# ─────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────

os.makedirs(RAW_DATA_FOLDER, exist_ok=True)
print(f"Output folder ready: {RAW_DATA_FOLDER}")


# ─────────────────────────────────────────────
# STEP 1 — Download full OHLCV data
# ─────────────────────────────────────────────

print(f"\nDownloading {len(ALL_TICKERS)} tickers from {START_DATE} to {END_DATE}...")
print(f"Delay between downloads: {DELAY_SECONDS} seconds to avoid rate limiting\n")

all_data       = {}
failed_tickers = []

for i, ticker in enumerate(ALL_TICKERS):
    print(f"  [{i+1}/{len(ALL_TICKERS)}] Downloading {ticker}...", end=" ")

    success = False
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            df = yf.download(ticker, start=START_DATE, end=END_DATE,
                             auto_adjust=False, progress=False)

            if df.empty:
                print(f"WARNING — no data returned (attempt {attempt})")
                time.sleep(DELAY_SECONDS * 2)
                continue

            df.index.name = 'Date'
            df = df.dropna(subset=['Adj Close'])

            # Flatten multi-level columns if present
            if isinstance(df.columns, pd.MultiIndex):
                df.columns = df.columns.get_level_values(0)

            # Save full OHLCV CSV
            csv_path = os.path.join(RAW_DATA_FOLDER, f"{ticker}.csv")
            df.to_csv(csv_path)
            print(f"OK — {len(df)} rows saved to {csv_path}")

            # Keep only Adj Close for SQL
            all_data[ticker] = df[['Adj Close']].copy()
            all_data[ticker].columns = ['adj_close']
            success = True
            break

        except Exception as e:
            if 'Rate' in str(e) or '429' in str(e):
                wait = DELAY_SECONDS * (attempt + 2)
                print(f"Rate limited (attempt {attempt}/{MAX_RETRIES}), waiting {wait}s...", end=" ")
                time.sleep(wait)
            else:
                print(f"ERROR — {e}")
                break

    if not success:
        print(f"FAILED after {MAX_RETRIES} attempts")
        failed_tickers.append(ticker)

    # Always wait between tickers
    if i < len(ALL_TICKERS) - 1:
        time.sleep(DELAY_SECONDS)

print(f"\nDownload complete. Success: {len(all_data)} | Failed: {len(failed_tickers)}")
if failed_tickers:
    print(f"Failed tickers: {failed_tickers}")


# ─────────────────────────────────────────────
# STEP 2 — Validate data
# ─────────────────────────────────────────────

print("\n--- DATA VALIDATION ---")
for ticker, df in all_data.items():
    print(f"  {ticker}: {len(df)} rows | "
          f"{df.index.min().date()} to {df.index.max().date()} | "
          f"adj close: {df['adj_close'].min():.2f} - {df['adj_close'].max():.2f}")


# ─────────────────────────────────────────────
# STEP 3 — Generate SQL INSERT file
# Only Adj Close inserted. Full OHLCV stays in CSV.
# ─────────────────────────────────────────────

if not all_data:
    print("\nNo data downloaded. SQL file not generated.")
    print("Wait a few minutes and run the script again.")
    exit()

print(f"\nGenerating SQL file: {SQL_OUTPUT_FILE}...")

total_rows = 0

with open(SQL_OUTPUT_FILE, 'w') as f:

    f.write(f"-- ============================================================\n")
    f.write(f"-- Portfolio Risk Analysis - Palo Alto Client\n")
    f.write(f"-- INSERT statements for {SCHEMA}.{TABLE}\n")
    f.write(f"-- Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    f.write(f"-- Tickers: {', '.join(ALL_TICKERS)}\n")
    f.write(f"-- Date range: {START_DATE} to {END_DATE}\n")
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

        for date, row in df.iterrows():
            value    = round(float(row['adj_close']), 6)
            date_str = date.strftime('%Y-%m-%d')
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

# ─────────────────────────────────────────────
# STEP 4 — Summary
# ─────────────────────────────────────────────

print("\n--- SUMMARY ---")
print(f"Portfolio tickers : {[t for t in PORTFOLIO_TICKERS if t in all_data]}")
print(f"Benchmark tickers : {[t for t in BENCHMARK_TICKERS if t in all_data]}")
print(f"CSV files (OHLCV) : {RAW_DATA_FOLDER}/")
print(f"SQL (Adj Close)   : {SQL_OUTPUT_FILE}")
print(f"\nNext steps:")
print(f"  1. Run script1.sql in MySQL Workbench")
print(f"  2. Run data/pricing_inserts.sql")
print(f"  3. Run script3.sql to create stored procedures")
print(f"  4. CALL paloalto_client.sp_portfolio_analysis(12);")
