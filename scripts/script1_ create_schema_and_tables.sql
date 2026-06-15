/* =========================================================================================
   SCRIPT 1 - CREATE SCHEMA AND TABLES
   Client:   Palo Alto UHNW Client
   Schema:   paloalto_client
   Author:   Juanjo Chiarella
   Course:   Data Management & SQL - DAT 5486
   Date:     June 2026

   Naming conventions:
   dim_  = dimension tables. Descriptive data that does not change often.
   fct_  = fact tables. Transactional or event data.
   rpt_  = report tables. Pre-calculated results for analysis.
   sp_   = stored procedures.

   Business processes reflected in this schema:
   1. Register the client          -> dim_client
   2. Define the securities        -> dim_ticker
   3. Record portfolio allocation  -> fct_holdings
   4. Load daily market prices     -> fct_pricing_daily
   5. Calculate daily returns      -> fct_daily_ror
   6. Store analysis results       -> rpt_stats, rpt_portfolio_summary, 
								   -> rpt_correlation_matrix, rpt_correlation
   7. Define rebalanced portfolio  -> dim_rebalanced_weights
========================================================================================= */
-- #DANGER: uncommenting the line below will delete the entire schema
-- DROP SCHEMA IF EXISTS paloalto_client;
CREATE SCHEMA IF NOT EXISTS paloalto_client;
USE paloalto_client;
/* -----------------------------------------------------------------------------------------
   dim_client
   Stores client information.
   customer_id as PK supports multiple clients in the future.
----------------------------------------------------------------------------------------- */
CREATE TABLE dim_client (
    customer_id    INT           NOT NULL AUTO_INCREMENT,
    full_name      VARCHAR(100)  NOT NULL,
    location       VARCHAR(100),
    total_aum_usd  DECIMAL(18,2) NOT NULL,
    PRIMARY KEY (customer_id)
);
/* -----------------------------------------------------------------------------------------
   dim_ticker
   Stores descriptive information for all securities in our analysis.
   is_benchmark = 1 for SPY, AGG, VT (market references, not client holdings).
   is_benchmark = 0 for IXN, QQQ, IEF, VNQ, GLD (client portfolio).
----------------------------------------------------------------------------------------- */
CREATE TABLE dim_ticker (
    ticker        VARCHAR(10)  NOT NULL,
    ticker_name   VARCHAR(100),
    asset_class   VARCHAR(50),
    is_benchmark  TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (ticker)
);
/* -----------------------------------------------------------------------------------------
   fct_pricing_daily
   Stores daily adjusted closing price for all 8 tickers.
   Only Adjusted Close is stored here — accounts for splits and dividends.
----------------------------------------------------------------------------------------- */
CREATE TABLE fct_pricing_daily (
    ticker  VARCHAR(10)   NOT NULL,
    date    DATE          NOT NULL,
    value   DECIMAL(12,6) NOT NULL,
    PRIMARY KEY (ticker, date),
    FOREIGN KEY (ticker) REFERENCES dim_ticker(ticker)
);
/* -----------------------------------------------------------------------------------------
   fct_holdings
   Stores the client portfolio allocation as percentages.
   We use allocation_pct instead of quantity because the professor provided
   the portfolio as percentage weights, not unit counts.
   value_usd = allocation_pct x 95,000,000.
----------------------------------------------------------------------------------------- */
CREATE TABLE fct_holdings (
    customer_id    INT           NOT NULL,
    ticker         VARCHAR(10)   NOT NULL,
    allocation_pct DECIMAL(5,4)  NOT NULL,
    value_usd      DECIMAL(15,2) NOT NULL,
    PRIMARY KEY (customer_id, ticker),
    FOREIGN KEY (customer_id) REFERENCES dim_client(customer_id),
    FOREIGN KEY (ticker)      REFERENCES dim_ticker(ticker)
);
/* -----------------------------------------------------------------------------------------
   fct_daily_ror
   Stores daily rate of return for each ticker calculated with LAG.
   We separate raw prices (fct_pricing_daily) from calculated returns (fct_daily_ror)
   following good data management practices — raw data should never be modified.
   Formula: ror = (price today / price yesterday) - 1
----------------------------------------------------------------------------------------- */
CREATE TABLE fct_daily_ror (
    ticker  VARCHAR(10)   NOT NULL,
    date    DATE          NOT NULL,
    value   DECIMAL(12,6) NOT NULL,
    p0      DECIMAL(12,6),
    ror     DECIMAL(18,10),
    PRIMARY KEY (ticker, date)
);
/* -----------------------------------------------------------------------------------------
   rpt_stats
   Stores expected return, risk and Sharpe Ratio per ticker per period.
   period_months = 12, 18 or 24 so all periods are comparable side by side.
   Includes all 8 tickers so we can compare portfolio holdings vs benchmarks.
----------------------------------------------------------------------------------------- */
CREATE TABLE rpt_stats (
    period_months  INT           NOT NULL,
    ticker         VARCHAR(10)   NOT NULL,
    expected_ror   DECIMAL(18,10),
    risk           DECIMAL(18,10),
    sharpe_ratio   DECIMAL(18,10),
    period_start   DATE,
    period_end     DATE,
    executed_at    DATETIME      NOT NULL,
    PRIMARY KEY (period_months, ticker)
);
/* -----------------------------------------------------------------------------------------
   rpt_portfolio_summary
   Stores weighted portfolio metrics per period.
   is_rebalanced = 0 means current weights from fct_holdings.
   is_rebalanced = 1 means new weights from sp_rebalanced_portfolio.
----------------------------------------------------------------------------------------- */
CREATE TABLE rpt_portfolio_summary (
    period_months        INT           NOT NULL,
    is_rebalanced        TINYINT(1)    NOT NULL DEFAULT 0,
    portfolio_expected_ror DECIMAL(18,10),
    portfolio_risk       DECIMAL(18,10),
    portfolio_sharpe     DECIMAL(18,10),
    as_of_date           DATE,
    executed_at          DATETIME      NOT NULL,
    PRIMARY KEY (period_months, is_rebalanced)
);
/* -----------------------------------------------------------------------------------------
   rpt_correlation_matrix and rpt_correlation
   Stores variance and Pearson correlation per ticker per period.
   Variance = STD^2, shows how much each asset fluctuates independently.
   Correlation vs each benchmark shows how much each asset moves with the market.
----------------------------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS paloalto_client.rpt_correlation_matrix (
    period_months  INT          NOT NULL,
    ticker_a       VARCHAR(10)  NOT NULL,
    ticker_b       VARCHAR(10)  NOT NULL,
    correlation    DECIMAL(10,6),
    executed_at    DATETIME     NOT NULL,
    PRIMARY KEY (period_months, ticker_a, ticker_b)
);

CREATE TABLE rpt_correlation (
    period_months  INT           NOT NULL,
    ticker         VARCHAR(10)   NOT NULL,
    variance       DECIMAL(18,10),
    risk           DECIMAL(18,10),
    corr_vs_spy    DECIMAL(10,6),
    corr_vs_agg    DECIMAL(10,6),
    corr_vs_vt     DECIMAL(10,6),
    executed_at    DATETIME      NOT NULL,
    PRIMARY KEY (period_months, ticker)
);
/* -----------------------------------------------------------------------------------------
   dim_rebalanced_weights
   Stores the tickers selected for the rebalanced portfolio.
   Pre-filled with all 8 tickers and include_in_rebalance = 0.
   You update include_in_rebalance = 1 for the tickers you want to include.
   sp_rebalanced_portfolio reads this table, applies Sharpe-proportional weights,
   and calculates the new portfolio metrics.
   Answers assignment questions 4 and 5.
----------------------------------------------------------------------------------------- */
CREATE TABLE dim_rebalanced_weights (
    ticker               VARCHAR(10)  NOT NULL,
    include_in_rebalance TINYINT(1)   NOT NULL DEFAULT 0,
    new_pct              DECIMAL(5,4),
    change_pct           DECIMAL(6,4),
    method               VARCHAR(50),
    executed_at          DATETIME,
    PRIMARY KEY (ticker),
    FOREIGN KEY (ticker) REFERENCES dim_ticker(ticker)
);
/* =========================================================================================
   VALIDATION
========================================================================================= */

SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'paloalto_client'
ORDER BY TABLE_NAME;
