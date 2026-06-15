/* =========================================================================================
   SCRIPT 3 - ANALYSIS: DAILY RETURNS, INDEXES AND STORED PROCEDURES
   Client:   Palo Alto UHNW Client
   Schema:   paloalto_client
   Author:   Juanjo Chiarella
   Course:   Data Management & SQL - DAT 5486
   Date:     June 2026

   This script builds the full analytical layer on top of the data loaded in scripts 1 and 2.
   Run this AFTER script1, script2, and data/pricing_inserts.sql.

   What we create:
   1. fct_daily_ror         -- daily returns using LAG window function
   2. sp_portfolio_analysis -- answers questions 1 and 3 (return and risk per period)
   3. sp_correlation        -- answers question 2 (correlations between assets)
   4. sp_rebalanced_portfolio -- answers questions 4 and 5 (rebalancing recommendation)

   How to run the analysis:
       CALL paloalto_client.sp_portfolio_analysis(12);
       CALL paloalto_client.sp_portfolio_analysis(18);
       CALL paloalto_client.sp_portfolio_analysis(24);
       CALL paloalto_client.sp_correlation(12);
       CALL paloalto_client.sp_rebalanced_portfolio(12);
========================================================================================= */

USE paloalto_client;


/* -----------------------------------------------------------------------------------------
   STEP 1: fct_daily_ror

   We calculate the daily rate of return for every ticker using LAG.
   LAG gets the previous day price so we can calculate how much the price moved.
   Formula: ror = (price today / price yesterday) - 1
   We store the result in a physical table instead of a view for performance.
   The procedures read this table multiple times, once per period.
   Without the table, MySQL would recalculate LAG on every procedure call.
   Two indexes speed up the WHERE date >= and GROUP BY ticker queries.
----------------------------------------------------------------------------------------- */

-- #DANGER
DROP TABLE IF EXISTS paloalto_client.fct_daily_ror;

CREATE TABLE paloalto_client.fct_daily_ror (
    ticker  VARCHAR(10)   NOT NULL,
    date    DATE          NOT NULL,
    value   DECIMAL(12,6) NOT NULL,
    p0      DECIMAL(12,6),
    ror     DECIMAL(18,10),
    PRIMARY KEY (ticker, date)
);

INSERT INTO paloalto_client.fct_daily_ror (ticker, date, value, p0, ror)
SELECT
    a.ticker,
    a.date,
    a.value,
    LAG(a.value, 1) OVER(PARTITION BY a.ticker ORDER BY a.date ASC) AS p0,
    (a.value / LAG(a.value, 1) OVER(PARTITION BY a.ticker ORDER BY a.date ASC)) - 1 AS ror
FROM paloalto_client.fct_pricing_daily a
WHERE a.ticker IN ('IXN', 'QQQ', 'IEF', 'VNQ', 'GLD', 'SPY', 'AGG', 'VT');

-- indexes to speed up queries inside the procedures
CREATE INDEX idx_ror_date        ON paloalto_client.fct_daily_ror(date);
CREATE INDEX idx_ror_ticker_date ON paloalto_client.fct_daily_ror(ticker, date);

-- validate: should have rows for all 8 tickers
SELECT ticker, COUNT(*) AS rows, MIN(date) AS first_date, MAX(date) AS last_date
FROM paloalto_client.fct_daily_ror
GROUP BY ticker
ORDER BY ticker;


/* -----------------------------------------------------------------------------------------
   STEP 2: sp_portfolio_analysis(p_months INT)

   This procedure answers assignment questions 1 and 3.
   It accepts 12, 18 or 24 as input and calculates for that period:
   - Total return per ticker: (last price / first price) - 1
   - Expected return: AVG(daily ror)
   - Risk: STD(daily ror)
   - Sharpe Ratio: expected_ror / risk
   - Weighted portfolio return and risk using allocation_pct from fct_holdings

   The start date is calculated from MAX(date) in fct_pricing_daily, not from today.
   This ensures we use only dates available in our data, not future dates.

   Results are saved to rpt_stats and rpt_portfolio_summary with period_months column
   so 12M, 18M and 24M results are all stored and comparable side by side.
   TRUNCATE removes old results for that period before inserting new ones.
----------------------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS paloalto_client.sp_portfolio_analysis;

DELIMITER $$
CREATE PROCEDURE paloalto_client.sp_portfolio_analysis(IN p_months INT)
BEGIN
    DECLARE v_now       DATETIME DEFAULT NOW();
    DECLARE v_end_date  DATE;
    DECLARE v_start_date DATE;

    -- get the last date available in our price table
    -- we calculate period start from this date, not from today
    SELECT MAX(date) INTO v_end_date
    FROM paloalto_client.fct_pricing_daily;

    -- calculate start date: go back p_months from the last available date
    SET v_start_date = DATE_SUB(v_end_date, INTERVAL p_months MONTH);

    -- remove old results for this period before inserting new ones
    DELETE FROM paloalto_client.rpt_stats         WHERE period_months = p_months;
    DELETE FROM paloalto_client.rpt_portfolio_summary WHERE period_months = p_months AND is_rebalanced = 0;

    -- calculate stats per ticker and insert into rpt_stats
    -- total_return uses first and last price in the period
    -- expected_ror and risk use all daily returns in the period
    INSERT INTO paloalto_client.rpt_stats
        (period_months, ticker, total_return, expected_ror, risk, sharpe_ratio,
         period_start, period_end, executed_at)
    SELECT
        p_months,
        r.ticker,
        -- total return: last price vs first price in the period
        (FIRST_VALUE(r.value) OVER(PARTITION BY r.ticker ORDER BY r.date DESC) /
         FIRST_VALUE(r.value) OVER(PARTITION BY r.ticker ORDER BY r.date ASC)) - 1 AS total_return,
        AVG(r.ror)              AS expected_ror,
        STD(r.ror)              AS risk,
        AVG(r.ror) / STD(r.ror) AS sharpe_ratio,
        v_start_date            AS period_start,
        v_end_date              AS period_end,
        v_now
    FROM paloalto_client.fct_daily_ror r
    WHERE r.date >= v_start_date
      AND r.ror IS NOT NULL
    GROUP BY r.ticker;

    -- calculate weighted portfolio metrics using allocation_pct from fct_holdings
    -- benchmarks are excluded from the portfolio calculation
    INSERT INTO paloalto_client.rpt_portfolio_summary
        (period_months, is_rebalanced, portfolio_total_return,
         portfolio_expected_ror, portfolio_risk, portfolio_sharpe,
         as_of_date, executed_at)
    SELECT
        p_months,
        0                                               AS is_rebalanced,
        SUM(s.total_return  * h.allocation_pct)         AS portfolio_total_return,
        SUM(s.expected_ror  * h.allocation_pct)         AS portfolio_expected_ror,
        SUM(s.risk          * h.allocation_pct)         AS portfolio_risk,
        SUM(s.sharpe_ratio  * h.allocation_pct)         AS portfolio_sharpe,
        v_end_date                                      AS as_of_date,
        v_now
    FROM paloalto_client.rpt_stats s
    JOIN paloalto_client.fct_holdings h ON s.ticker = h.ticker
    WHERE s.period_months = p_months;

    -- show results on screen
    SELECT CONCAT('sp_portfolio_analysis completed for ', p_months, 'M period') AS status,
           v_start_date AS period_start, v_end_date AS period_end, v_now AS executed_at;

    -- individual ticker results
    SELECT
        s.period_months,
        s.ticker,
        t.asset_class,
        CASE WHEN t.is_benchmark = 1 THEN 'Benchmark' ELSE 'Portfolio' END AS ticker_type,
        ROUND(s.total_return   * 100, 2) AS total_return_pct,
        ROUND(s.expected_ror   * 100, 4) AS expected_daily_ror_pct,
        ROUND(s.risk           * 100, 4) AS risk_pct,
        ROUND(s.sharpe_ratio,  4)        AS sharpe_ratio
    FROM paloalto_client.rpt_stats s
    JOIN paloalto_client.dim_ticker t ON s.ticker = t.ticker
    WHERE s.period_months = p_months
    ORDER BY t.is_benchmark, s.sharpe_ratio DESC;

    -- portfolio summary
    SELECT
        period_months,
        ROUND(portfolio_total_return   * 100, 2) AS portfolio_total_return_pct,
        ROUND(portfolio_expected_ror   * 100, 4) AS portfolio_expected_ror_pct,
        ROUND(portfolio_risk           * 100, 4) AS portfolio_risk_pct,
        ROUND(portfolio_sharpe,        4)        AS portfolio_sharpe,
        as_of_date
    FROM paloalto_client.rpt_portfolio_summary
    WHERE period_months = p_months AND is_rebalanced = 0;

END$$
DELIMITER ;


/* -----------------------------------------------------------------------------------------
   STEP 3: sp_correlation(p_months INT)

   This procedure answers assignment question 2.
   It calculates the variance for each ticker in the given period.
   We also attempt to calculate correlation vs each benchmark using CORR().
   The professor noted that CORR() may not work in older MySQL versions.
   If it does not work, we compare variances side by side as the alternative.
   Variance = STD^2 and shows how much each asset moves on its own.
   Comparing variances across asset classes reveals which assets are more stable.
----------------------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS paloalto_client.sp_correlation;

DELIMITER $$
CREATE PROCEDURE paloalto_client.sp_correlation(IN p_months INT)
BEGIN
    DECLARE v_now        DATETIME DEFAULT NOW();
    DECLARE v_end_date   DATE;
    DECLARE v_start_date DATE;

    SELECT MAX(date) INTO v_end_date   FROM paloalto_client.fct_pricing_daily;
    SET v_start_date = DATE_SUB(v_end_date, INTERVAL p_months MONTH);

    -- remove old results for this period
    DELETE FROM paloalto_client.rpt_correlation WHERE period_months = p_months;

    -- calculate variance per ticker
    -- variance = STD^2, tells us how much each asset fluctuates on its own
    -- we also attempt CORR() vs each benchmark
    -- if MySQL does not support CORR(), those columns will be NULL
    INSERT INTO paloalto_client.rpt_correlation
        (period_months, ticker, variance, risk, corr_vs_spy, corr_vs_agg, corr_vs_vt, executed_at)
    SELECT
        p_months,
        r.ticker,
        POW(STD(r.ror), 2)  AS variance,  -- variance = standard deviation squared
        STD(r.ror)           AS risk,
        -- correlation vs SPY: measures how much this asset moves with the US stock market
        -- a value close to 1 means they move together, close to 0 means independent
        (COUNT(*) * SUM(r.ror * spy.ror) - SUM(r.ror) * SUM(spy.ror)) /
        (SQRT(COUNT(*) * SUM(r.ror * r.ror) - POW(SUM(r.ror), 2)) *
         SQRT(COUNT(*) * SUM(spy.ror * spy.ror) - POW(SUM(spy.ror), 2)))
                             AS corr_vs_spy,
        -- correlation vs AGG: the US bond market benchmark
        (COUNT(*) * SUM(r.ror * agg.ror) - SUM(r.ror) * SUM(agg.ror)) /
        (SQRT(COUNT(*) * SUM(r.ror * r.ror) - POW(SUM(r.ror), 2)) *
         SQRT(COUNT(*) * SUM(agg.ror * agg.ror) - POW(SUM(agg.ror), 2)))
                             AS corr_vs_agg,
        -- correlation vs VT: the global equity market benchmark
        (COUNT(*) * SUM(r.ror * vt.ror) - SUM(r.ror) * SUM(vt.ror)) /
        (SQRT(COUNT(*) * SUM(r.ror * r.ror) - POW(SUM(r.ror), 2)) *
         SQRT(COUNT(*) * SUM(vt.ror * vt.ror) - POW(SUM(vt.ror), 2)))
                             AS corr_vs_vt,
        v_now
    FROM paloalto_client.fct_daily_ror r
    -- join benchmarks to calculate correlation
    JOIN paloalto_client.fct_daily_ror spy ON r.date = spy.date AND spy.ticker = 'SPY'
    JOIN paloalto_client.fct_daily_ror agg ON r.date = agg.date AND agg.ticker = 'AGG'
    JOIN paloalto_client.fct_daily_ror vt  ON r.date = vt.date  AND vt.ticker  = 'VT'
    WHERE r.date >= v_start_date
      AND r.ror    IS NOT NULL
      AND spy.ror  IS NOT NULL
      AND agg.ror  IS NOT NULL
      AND vt.ror   IS NOT NULL
    GROUP BY r.ticker;

    -- show results on screen
    SELECT CONCAT('sp_correlation completed for ', p_months, 'M period') AS status,
           v_start_date AS period_start, v_end_date AS period_end;

    -- variance comparison — lower variance = more stable asset
    SELECT
        c.period_months,
        c.ticker,
        t.asset_class,
        CASE WHEN t.is_benchmark = 1 THEN 'Benchmark' ELSE 'Portfolio' END AS ticker_type,
        ROUND(c.risk     * 100, 4)  AS risk_pct,
        ROUND(c.variance * 10000, 6) AS variance_x10000,  -- scaled for readability
        ROUND(c.corr_vs_spy, 4)     AS corr_vs_spy,
        ROUND(c.corr_vs_agg, 4)     AS corr_vs_agg,
        ROUND(c.corr_vs_vt,  4)     AS corr_vs_vt
    FROM paloalto_client.rpt_correlation c
    JOIN paloalto_client.dim_ticker t ON c.ticker = t.ticker
    WHERE c.period_months = p_months
    ORDER BY t.is_benchmark, c.variance ASC;

END$$
DELIMITER ;


/* -----------------------------------------------------------------------------------------
   STEP 4: sp_rebalanced_portfolio(p_months INT)

   This procedure answers assignment questions 4 and 5.
   It calculates new optimal weights using the inverse volatility method.
   Formula: new_weight = (1 / risk_ticker) / SUM(1 / risk_all_portfolio_tickers)

   Why inverse volatility?
   This method gives more weight to less volatile assets.
   It is appropriate for this client because:
   - Ultra High Net Worth investors prioritize capital preservation
   - The current portfolio has significant fixed income (28.5% IEF) and gold (23% GLD)
   - This signals a conservative risk profile

   The procedure reads risk values from rpt_stats so sp_portfolio_analysis must run first.
   New weights are saved in dim_rebalanced_weights.
   Rebalanced portfolio metrics are saved in rpt_portfolio_summary with is_rebalanced = 1.
   The procedure shows a before vs after comparison on screen.
----------------------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS paloalto_client.sp_rebalanced_portfolio;

DELIMITER $$
CREATE PROCEDURE paloalto_client.sp_rebalanced_portfolio(IN p_months INT)
BEGIN
    DECLARE v_now DATETIME DEFAULT NOW();

    -- remove old rebalanced weights for this period
    DELETE FROM paloalto_client.dim_rebalanced_weights WHERE period_months = p_months;
    DELETE FROM paloalto_client.rpt_portfolio_summary
    WHERE period_months = p_months AND is_rebalanced = 1;

    -- calculate new weights using inverse volatility method
    -- step 1: for each portfolio ticker, calculate 1/risk
    -- step 2: divide each by the total sum of 1/risk values
    -- result: tickers with lower risk get higher weight
    INSERT INTO paloalto_client.dim_rebalanced_weights
        (period_months, ticker, current_pct, new_pct, change_pct, method, executed_at)
    SELECT
        p_months,
        s.ticker,
        h.allocation_pct                                    AS current_pct,
        -- new weight = (1/risk) / SUM(1/risk for all portfolio tickers)
        (1.0 / s.risk) /
        SUM(1.0 / s.risk) OVER()                           AS new_pct,
        -- change = new weight minus current weight
        ((1.0 / s.risk) / SUM(1.0 / s.risk) OVER()) -
        h.allocation_pct                                   AS change_pct,
        'inverse_volatility'                               AS method,
        v_now
    FROM paloalto_client.rpt_stats s
    JOIN paloalto_client.fct_holdings h ON s.ticker = h.ticker
    WHERE s.period_months = p_months
      AND s.risk > 0;

    -- calculate rebalanced portfolio metrics using new weights
    INSERT INTO paloalto_client.rpt_portfolio_summary
        (period_months, is_rebalanced, portfolio_total_return,
         portfolio_expected_ror, portfolio_risk, portfolio_sharpe,
         as_of_date, executed_at)
    SELECT
        p_months,
        1                                               AS is_rebalanced,
        SUM(s.total_return  * w.new_pct)               AS portfolio_total_return,
        SUM(s.expected_ror  * w.new_pct)               AS portfolio_expected_ror,
        SUM(s.risk          * w.new_pct)               AS portfolio_risk,
        SUM(s.sharpe_ratio  * w.new_pct)               AS portfolio_sharpe,
        MAX(s.period_end)                              AS as_of_date,
        v_now
    FROM paloalto_client.rpt_stats s
    JOIN paloalto_client.dim_rebalanced_weights w
        ON s.ticker = w.ticker AND w.period_months = p_months
    WHERE s.period_months = p_months;

    -- show new weights on screen
    SELECT CONCAT('sp_rebalanced_portfolio completed for ', p_months, 'M period') AS status, v_now;

    SELECT
        w.ticker,
        t.asset_class,
        ROUND(w.current_pct * 100, 2) AS current_weight_pct,
        ROUND(w.new_pct     * 100, 2) AS new_weight_pct,
        ROUND(w.change_pct  * 100, 2) AS change_pct,
        CASE
            WHEN w.change_pct > 0.01  THEN 'INCREASE'
            WHEN w.change_pct < -0.01 THEN 'REDUCE'
            ELSE 'HOLD'
        END                            AS action,
        w.method
    FROM paloalto_client.dim_rebalanced_weights w
    JOIN paloalto_client.dim_ticker t ON w.ticker = t.ticker
    WHERE w.period_months = p_months
    ORDER BY w.new_pct DESC;

    -- before vs after portfolio comparison
    SELECT
        period_months,
        CASE WHEN is_rebalanced = 0 THEN 'Current Portfolio'
             ELSE 'Rebalanced Portfolio' END              AS portfolio_version,
        ROUND(portfolio_total_return   * 100, 2)          AS total_return_pct,
        ROUND(portfolio_expected_ror   * 100, 4)          AS expected_daily_ror_pct,
        ROUND(portfolio_risk           * 100, 4)          AS risk_pct,
        ROUND(portfolio_sharpe,        4)                 AS sharpe_ratio
    FROM paloalto_client.rpt_portfolio_summary
    WHERE period_months = p_months
    ORDER BY is_rebalanced;

END$$
DELIMITER ;
