/* =========================================================================================
   SCRIPT 1 - CREATE SCHEMA AND TABLES
   Client:   Palo Alto UHNW Client
   Schema:   paloalto_client
   Author:   Juanjo Chiarella
   Course:   Data Management & SQL - DAT 5486
   Date:     June 2026

   Naming conventions used in this schema:
   dim_   = dimension tables. Descriptive data that does not change often.
   fct_   = fact tables. Transactional or event data.
   rpt_   = report tables. Pre-calculated results for analysis.
   sp_    = stored procedures.
   fn_    = functions.

   Business processes reflected in this schema:
   1. Register the client             -> dim_client
   2. Define the securities           -> dim_ticker
   3. Record portfolio allocation     -> fct_holdings
   4. Load daily market prices        -> fct_pricing_daily
   5. Calculate daily returns         -> fct_daily_ror
   6. Store analysis results          -> rpt_stats, rpt_portfolio_summary, rpt_correlation
   7. Store rebalanced weights        -> dim_rebalanced_weights
========================================================================================= */

-- #DANGER: uncommenting the line below will delete the entire schema and all data
-- DROP SCHEMA IF EXISTS paloalto_client;

CREATE SCHEMA IF NOT EXISTS paloalto_client;
USE paloalto_client;


/* -----------------------------------------------------------------------------------------
   dim_client
   Stores the client information.
   We use customer_id as PK so the schema can support multiple clients in the future.
   Right now we only have one client based in Palo Alto, CA.
----------------------------------------------------------------------------------------- */
-- DROP TABLE IF EXISTS dim_client; -- #DANGER
CREATE TABLE dim_client (
    customer_id       INT           NOT NULL AUTO_INCREMENT,
    full_name         VARCHAR(100)  NOT NULL,
    location          VARCHAR(100),
    total_aum_usd     DECIMAL(18,2) NOT NULL,
    PRIMARY KEY (customer_id)
);


/* -----------------------------------------------------------------------------------------
   dim_ticker
   Stores descriptive information about each security in our analysis.
   is_benchmark = 1 means this ticker is used as a market reference, not a client holding.
   Portfolio tickers: IXN, QQQ, IEF, VNQ, GLD
   Benchmark tickers: SPY, AGG, VT
----------------------------------------------------------------------------------------- */
-- DROP TABLE IF EXISTS dim_ticker; -- #DANGER
CREATE TABLE dim_ticker (
    ticker            VARCHAR(10)   NOT NULL,
    ticker_name       VARCHAR(100),
    asset_class       VARCHAR(50),
    is_benchmark      TINYINT(1)    NOT NULL DEFAULT 0,
    PRIMARY KEY (ticker)
);


/* -----------------------------------------------------------------------------------------
   fct_pricing_daily
   Stores the daily adjusted closing price for each security.
   One row per ticker per day. Only Adjusted Close is stored here.
   Full OHLCV data is available in /data/raw/ CSV files.
----------------------------------------------------------------------------------------- */
-- DROP TABLE IF EXISTS fct_pricing_daily; -- #DANGER
CREATE TABLE fct_pricing_daily (
    ticker            VARCHAR(10)   NOT NULL,
    date              DATE          NOT NULL,
    value             DECIMAL(12,6) NOT NULL,
    PRIMARY KEY (ticker, date),
    FOREIGN KEY (ticker) REFERENCES dim_ticker(ticker)
);


/* -----------------------------------------------------------------------------------------
   fct_holdings
   Stores the client portfolio allocation as percentages.
   We use allocation_pct instead of quantity because the professor provided
   the portfolio as percentage weights, not unit counts.
   value_usd = allocation_pct x 95,000,000 (total AUM).
   customer_id FK links to dim_client and supports multiple clients in the future.
----------------------------------------------------------------------------------------- */
-- DROP TABLE IF EXISTS fct_holdings; -- #DANGER
CREATE TABLE fct_holdings (
    customer_id       INT           NOT NULL,
    ticker            VARCHAR(10)   NOT NULL,
    allocation_pct    DECIMAL(5,4)  NOT NULL,
    value_usd         DECIMAL(15,2) NOT NULL,
    PRIMARY KEY (customer_id, ticker),
    FOREIGN KEY (customer_id) REFERENCES dim_client(customer_id),
    FOREIGN KEY (ticker)      REFERENCES dim_ticker(ticker)
);


/* -----------------------------------------------------------------------------------------
   fct_daily_ror
   Stores the daily rate of return for each ticker.
   We use a physical table instead of a view for performance.
   The stored procedures read this table multiple times, once per period.
   Formula: ror = (price today / price yesterday) - 1
   First row per ticker has NULL for ror because LAG has no previous row.
   Two indexes speed up the WHERE date >= queries inside the procedures.
----------------------------------------------------------------------------------------- */
-- DROP TABLE IF EXISTS fct_daily_ror; -- #DANGER
CREATE TABLE fct_daily_ror (
    ticker            VARCHAR(10)   NOT NULL,
    date              DATE          NOT NULL,
    value             DECIMAL(12,6) NOT NULL,
    p0                DECIMAL(12,6),
    ror               DECIMAL(18,10),
    PRIMARY KEY (ticker, date)
);


/* -----------------------------------------------------------------------------------------
   rpt_stats
   Stores return, risk and Sharpe Ratio for each ticker per period.
   period_months stores 12, 18 or 24 so all periods are in the same table
   and can be compared side by side.
   executed_at is the audit trail — tells us when the procedure last ran.
   Answers assignment questions 1 and 3.
----------------------------------------------------------------------------------------- */
-- DROP TABLE IF EXISTS rpt_stats; -- #DANGER
CREATE TABLE rpt_stats (
    period_months     INT           NOT NULL,
    ticker            VARCHAR(10)   NOT NULL,
    total_return      DECIMAL(18,10),
    expected_ror      DECIMAL(18,10),
    risk              DECIMAL(18,10),
    sharpe_ratio      DECIMAL(18,10),
    period_start      DATE,
    period_end        DATE,
    executed_at       DATETIME      NOT NULL,
    PRIMARY KEY (period_months, ticker)
);


/* -----------------------------------------------------------------------------------------
   rpt_portfolio_summary
   Stores weighted portfolio-level metrics per period.
   is_rebalanced = 0 means current weights, 1 means new optimal weights.
   This lets us compare before vs after rebalancing in the same table.
   Answers assignment questions 1, 3 and 5.
----------------------------------------------------------------------------------------- */
-- DROP TABLE IF EXISTS rpt_portfolio_summary; -- #DANGER
CREATE TABLE rpt_portfolio_summary (
    period_months          INT           NOT NULL,
    is_rebalanced          TINYINT(1)    NOT NULL DEFAULT 0,
    portfolio_total_return DECIMAL(18,10),
    portfolio_expected_ror DECIMAL(18,10),
    portfolio_risk         DECIMAL(18,10),
    portfolio_sharpe       DECIMAL(18,10),
    as_of_date             DATE,
    executed_at            DATETIME      NOT NULL,
    PRIMARY KEY (period_months, is_rebalanced)
);


/* -----------------------------------------------------------------------------------------
   rpt_correlation
   Stores variance and correlation analysis per ticker per period.
   The professor noted that MySQL CORR() may not work in older versions.
   If CORR() works we store full correlations vs each benchmark.
   If not, we compare variances side by side as the alternative.
   Answers assignment question 2.
----------------------------------------------------------------------------------------- */
-- DROP TABLE IF EXISTS rpt_correlation; -- #DANGER
CREATE TABLE rpt_correlation (
    period_months     INT           NOT NULL,
    ticker            VARCHAR(10)   NOT NULL,
    variance          DECIMAL(18,10),
    risk              DECIMAL(18,10),
    corr_vs_spy       DECIMAL(10,6),
    corr_vs_agg       DECIMAL(10,6),
    corr_vs_vt        DECIMAL(10,6),
    executed_at       DATETIME      NOT NULL,
    PRIMARY KEY (period_months, ticker)
);


/* -----------------------------------------------------------------------------------------
   dim_rebalanced_weights
   Stores the new optimal weights calculated by sp_rebalanced_portfolio.
   method = the formula used (inverse_volatility).
   change_pct = new_pct - current_pct, shows the direction of the rebalancing.
   Answers assignment questions 4 and 5.
----------------------------------------------------------------------------------------- */
-- DROP TABLE IF EXISTS dim_rebalanced_weights; -- #DANGER
CREATE TABLE dim_rebalanced_weights (
    period_months     INT           NOT NULL,
    ticker            VARCHAR(10)   NOT NULL,
    current_pct       DECIMAL(5,4)  NOT NULL,
    new_pct           DECIMAL(5,4)  NOT NULL,
    change_pct        DECIMAL(6,4),
    method            VARCHAR(50),
    executed_at       DATETIME      NOT NULL,
    PRIMARY KEY (period_months, ticker),
    FOREIGN KEY (ticker) REFERENCES dim_ticker(ticker)
);


/* =========================================================================================
   VALIDATION
========================================================================================= */

SELECT TABLE_NAME, TABLE_TYPE
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'paloalto_client'
ORDER BY TABLE_TYPE, TABLE_NAME;
