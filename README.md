# Investment Portfolio Risk Analysis
### SQL and Python | Palo Alto UHNW Client

**Author:** Juanjo Chiarella  
**Program:** MBA — Hult International Business School  
**Course:** Data Management and SQL (DAT 5486)  
**Professor:** Thomas Kurnicki  
**Date:** June 2026

---

## Overview

This project analyzes the portfolio of an Ultra High Net Worth client based in Palo Alto, California, with $95 million in liquid assets. The goal is to evaluate whether each holding is earning its place on a risk-adjusted basis and to deliver a data-backed rebalancing recommendation.

The entire analysis was built in MySQL using stored procedures that accept a time window parameter (12, 18, or 24 months). Data was extracted from Yahoo Finance using Python.

---

## Client Portfolio

| Ticker | Name | Asset Class | Allocation | Value (USD) |
|--------|------|-------------|------------|-------------|
| IEF | iShares 7-10Y Treasury Bond ETF | Fixed Income | 28.50% | $27,075,000 |
| GLD | SPDR Gold Shares | Commodities | 23.00% | $21,850,000 |
| QQQ | Invesco NASDAQ 100 ETF | Equity | 22.10% | $20,995,000 |
| IXN | iShares Global Tech ETF | Equity | 17.50% | $16,625,000 |
| VNQ | Vanguard Real Estate ETF | Real Assets | 8.90% | $8,455,000 |

Benchmarks added for comparison: SPY, AGG, VT.

---

## Tech Stack

- **Python** — yfinance, pandas (data download from Yahoo Finance)
- **MySQL 8.x** — schema design, stored procedures, window functions, CTEs
- **MySQL Workbench** — local execution and validation

---

## Database Structure

**Schema:** `paloalto_client`

### Dimension and Fact Tables

| Table | Type | Description |
|-------|------|-------------|
| dim_client | Dimension | Client profile: name, location, total AUM |
| dim_ticker | Dimension | All 8 tickers with is_benchmark flag |
| dim_rebalanced_weights | Dimension | Rebalancing decisions and new allocations |
| fct_holdings | Fact | Current portfolio allocation as % and USD |
| fct_pricing_daily | Fact | Daily adjusted close price, 614 rows per ticker |
| fct_daily_ror | Fact | Daily rate of return via LAG() window function |

### Report Tables (Outputs)

| Table | Description |
|-------|-------------|
| rpt_stats | Expected return, risk, and Sharpe Ratio per ticker for 12M, 18M, 24M |
| rpt_portfolio_summary | Weighted portfolio metrics — current and rebalanced |
| rpt_correlation_matrix | Pearson correlation between each pair of portfolio holdings |
| rpt_correlation | Pearson correlation of each ticker vs SPY, AGG, VT |

### Stored Procedures

| Procedure | Input | Description |
|-----------|-------|-------------|
| sp_portfolio_analysis | p_months INT | Calculates expected return, risk, and Sharpe Ratio for all tickers |
| sp_correlation_matrix | p_months INT | Calculates internal Pearson correlation between the 5 portfolio holdings |
| sp_correlation | p_months INT | Calculates Pearson correlation of each ticker vs 3 benchmarks |
| sp_rebalanced_portfolio | p_months INT | Applies Sharpe-proportional weights and calculates new portfolio metrics |

---

## Scripts

| Script | Description |
|--------|-------------|
| script1_create_schema_and_tables.sql | Creates the paloalto_client schema and all 10 tables |
| script2_insert_into_dim.sql | Inserts client, tickers, holdings, and rebalancing configuration |
| script3_insert_into_daily_pricing.sql | Loads 614 daily adjusted close price records per ticker |
| script4_analysis_procedures.sql | Creates the 4 stored procedures |
| script5_reports.sql | Calls all procedures, updates rebalancing config, runs SELECT reports |
| script6_sp_correlation_matrix.sql | Creates sp_correlation_matrix procedure |
| download_data.py | Downloads adjusted close price from Yahoo Finance for all 8 tickers |

---

## How to Run

1. Run `download_data.py` to download pricing data from Yahoo Finance
2. Execute `script1` to create the schema and tables
3. Execute `script2` to insert dimension and fact data
4. Execute `script3` to load daily pricing data
5. Execute `script4` to create the stored procedures
6. Execute `script5` to run the full analysis:

```sql
-- Run analysis for all periods
CALL paloalto_client.sp_portfolio_analysis(12);
CALL paloalto_client.sp_portfolio_analysis(18);
CALL paloalto_client.sp_portfolio_analysis(24);

CALL paloalto_client.sp_correlation(12);
CALL paloalto_client.sp_correlation(18);
CALL paloalto_client.sp_correlation(24);

CALL paloalto_client.sp_correlation_matrix(12);
CALL paloalto_client.sp_correlation_matrix(18);
CALL paloalto_client.sp_correlation_matrix(24);

-- Update rebalancing selection
UPDATE paloalto_client.dim_rebalanced_weights
SET include_in_rebalance = 1
WHERE ticker IN ('IXN', 'QQQ', 'GLD', 'VNQ', 'VT', 'AGG');

UPDATE paloalto_client.dim_rebalanced_weights
SET include_in_rebalance = 0
WHERE ticker IN ('IEF', 'SPY');

-- Run rebalanced portfolio for all periods
CALL paloalto_client.sp_rebalanced_portfolio(12);
CALL paloalto_client.sp_rebalanced_portfolio(18);
CALL paloalto_client.sp_rebalanced_portfolio(24);
```

---

## Key Findings

### Rebalancing Recommendation

| Ticker | Asset Class | Current % | New % | Action |
|--------|-------------|-----------|-------|--------|
| IEF | Fixed Income | 28.50% | 0.00% | REMOVE |
| GLD | Commodities | 23.00% | 20.25% | REDUCE |
| QQQ | Equity | 22.10% | 16.33% | REDUCE |
| IXN | Equity | 17.50% | 17.13% | HOLD |
| VNQ | Real Assets | 8.90% | 12.60% | INCREASE |
| VT | Equity | 0.00% | 18.19% | ADD |
| AGG | Fixed Income | 0.00% | 15.49% | ADD |

### Portfolio Impact

| Period | Current Return % | Current Risk % | Rebalanced Return % | Rebalanced Risk % | Return Change |
|--------|-----------------|----------------|--------------------|--------------------|---------------|
| 12M | 0.0969% | 1.0593% | 0.1130% | 1.0583% | +16.6% |
| 18M | 0.0832% | 1.1745% | 0.0928% | 1.2567% | +11.5% |
| 24M | 0.0834% | 1.1259% | 0.0881% | 1.1605% | +5.6% |

---

## Naming Conventions

- `dim_` — Dimension tables: descriptive, slow-changing data
- `fct_` — Fact tables: transactional or event data
- `rpt_` — Report tables: pre-calculated results for analysis
- `sp_` — Stored procedures
