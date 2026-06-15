/* =========================================================================================
   SCRIPT 4 - ANALYSIS PROCEDURES
   Client:   Palo Alto UHNW Client
   Schema:   paloalto_client
   Author:   Juanjo Chiarella
   Course:   Data Management & SQL - DAT 5486
   Date:     June 2026

   Run this AFTER script1, script2 and script3 (pricing inserts).

   What we create:
   1. fct_daily_ror           -- daily returns using LAG window function
   2. sp_portfolio_analysis   -- answers questions 1 and 3
   3. sp_correlation          -- answers question 2
   4. sp_rebalanced_portfolio -- answers questions 4 and 5

   How to run:
       CALL paloalto_client.sp_portfolio_analysis(12);
       CALL paloalto_client.sp_portfolio_analysis(18);
       CALL paloalto_client.sp_portfolio_analysis(24);
       CALL paloalto_client.sp_correlation(12);
       CALL paloalto_client.sp_correlation(18);
       CALL paloalto_client.sp_correlation(24);

   Then review results, update dim_rebalanced_weights, and run:
       CALL paloalto_client.sp_rebalanced_portfolio(12);
========================================================================================= */

USE paloalto_client;


/* -----------------------------------------------------------------------------------------
   STEP 1: fct_daily_ror

   We calculate the daily return for each ticker using LAG.
   LAG gets the previous day price to calculate the daily movement.
   Formula: ror = (today price / yesterday price) - 1
   We separate raw prices (fct_pricing_daily) from calculated returns (fct_daily_ror)
   because raw data should never be modified — it is our source of truth.
   Two indexes speed up the WHERE date >= queries inside the procedures.
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

CREATE INDEX idx_ror_date        ON paloalto_client.fct_daily_ror(date);
CREATE INDEX idx_ror_ticker_date ON paloalto_client.fct_daily_ror(ticker, date);

-- validation
SELECT ticker, COUNT(*) AS num_rows, MIN(date) AS first_date, MAX(date) AS last_date
FROM paloalto_client.fct_daily_ror
GROUP BY ticker ORDER BY ticker;


/* -----------------------------------------------------------------------------------------
   STEP 2: sp_portfolio_analysis(p_months INT)

   Answers assignment questions 1 and 3.
   Accepts 12, 18 or 24 as input.

   Calculates for ALL 8 tickers (portfolio + benchmarks):
     - expected_ror : AVG(daily ror) in the period
     - risk         : STD(daily ror) in the period
     - sharpe_ratio : expected_ror / risk

   Then calculates weighted portfolio metrics using allocation_pct from fct_holdings.
   Benchmarks are excluded from the portfolio weighted calculation because they
   are not in fct_holdings — they are market references, not client holdings.

   Period start is calculated from MAX(date) in fct_pricing_daily, not from today.
   Results saved to rpt_stats and rpt_portfolio_summary with period_months column
   so 12M, 18M and 24M results are all stored and comparable side by side.
----------------------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS paloalto_client.sp_portfolio_analysis;

DELIMITER $$
CREATE PROCEDURE paloalto_client.sp_portfolio_analysis(IN p_months INT)
BEGIN
    DECLARE v_now        DATETIME DEFAULT NOW();
    DECLARE v_end_date   DATE;
    DECLARE v_start_date DATE;
    
    -- get last available date and calculate period start
    SELECT MAX(date) INTO v_end_date FROM paloalto_client.fct_pricing_daily;
    SET v_start_date = DATE_SUB(v_end_date, INTERVAL p_months MONTH);

    -- clean previous results for this period
    DELETE FROM paloalto_client.rpt_stats
    WHERE period_months = p_months;
    DELETE FROM paloalto_client.rpt_portfolio_summary
    WHERE period_months = p_months AND is_rebalanced = 0;

    -- calculate stats for all 8 tickers
    INSERT INTO paloalto_client.rpt_stats
        (period_months, ticker, expected_ror, risk, sharpe_ratio,
         period_start, period_end, executed_at)
    SELECT
        p_months,
        ticker,
        AVG(ror)            AS expected_ror,
        STD(ror)            AS risk,
        AVG(ror) / STD(ror) AS sharpe_ratio,
        v_start_date        AS period_start,
        v_end_date          AS period_end,
        v_now
    FROM paloalto_client.fct_daily_ror
    WHERE date >= v_start_date
      AND ror IS NOT NULL
    GROUP BY ticker;

    -- calculate weighted portfolio metrics using allocation_pct from fct_holdings
    -- benchmarks are automatically excluded because they are not in fct_holdings
    INSERT INTO paloalto_client.rpt_portfolio_summary
        (period_months, is_rebalanced, portfolio_expected_ror,
        portfolio_risk, portfolio_sharpe, as_of_date, executed_at)
    SELECT
        p_months,
        0,
        SUM(s.expected_ror  * h.allocation_pct),
        SUM(s.risk          * h.allocation_pct),
        SUM(s.sharpe_ratio  * h.allocation_pct),
        v_end_date,
        v_now
    FROM paloalto_client.rpt_stats s
    JOIN paloalto_client.fct_holdings h ON s.ticker = h.ticker
    WHERE s.period_months = p_months;
    
    -- show status
    SELECT CONCAT('sp_portfolio_analysis completed for ', p_months, 'M') AS status,
           v_start_date AS period_start, v_end_date AS period_end, v_now AS executed_at;
    -- show all 8 tickers ranked by Sharpe
    SELECT
        s.period_months,
        s.ticker,
        t.ticker_name,
        t.asset_class,
        CASE WHEN t.is_benchmark = 1 THEN 'Benchmark' ELSE 'Portfolio' END AS ticker_type,
        ROUND(s.expected_ror  * 100, 4) AS expected_daily_ror_pct,
        ROUND(s.risk          * 100, 4) AS risk_pct,
        ROUND(s.sharpe_ratio, 4)        AS sharpe_ratio,
        s.period_start,
        s.period_end
    FROM paloalto_client.rpt_stats s
    JOIN paloalto_client.dim_ticker t ON s.ticker = t.ticker
    WHERE s.period_months = p_months
    ORDER BY t.is_benchmark, s.sharpe_ratio DESC;

    -- show weighted portfolio summary
    SELECT
        period_months,
        ROUND(portfolio_expected_ror * 100, 4) AS portfolio_expected_ror_pct,
        ROUND(portfolio_risk         * 100, 4) AS portfolio_risk_pct,
        ROUND(portfolio_sharpe,      4)        AS portfolio_sharpe,
        as_of_date
    FROM paloalto_client.rpt_portfolio_summary
    WHERE period_months = p_months AND is_rebalanced = 0;

END$$
DELIMITER ;


/* -----------------------------------------------------------------------------------------
   STEP 3: sp_correlation(p_months INT)

   Answers assignment question 2.
   Calculates variance and Pearson correlation for each ticker in the given period.

   Variance = STD^2. Shows how much each asset fluctuates on its own.
   Lower variance = more stable asset.

   Pearson correlation vs each benchmark:
   - Close to  1 = moves with the benchmark (not diversified)
   - Close to  0 = independent from the benchmark (good diversification)
   - Close to -1 = moves opposite to the benchmark (excellent hedge)

   We implement Pearson correlation manually using the standard formula
   because MySQL CORR() may not be available in older versions.
----------------------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS paloalto_client.sp_correlation;

DELIMITER $$
CREATE PROCEDURE paloalto_client.sp_correlation(IN p_months INT)
BEGIN
    DECLARE v_now        DATETIME DEFAULT NOW();
    DECLARE v_end_date   DATE;
    DECLARE v_start_date DATE;

    SELECT MAX(date) INTO v_end_date FROM paloalto_client.fct_pricing_daily;
    SET v_start_date = DATE_SUB(v_end_date, INTERVAL p_months MONTH);

    DELETE FROM paloalto_client.rpt_correlation WHERE period_months = p_months;

    -- calculate variance and Pearson correlation vs each benchmark
    -- Pearson formula: corr(X,Y) = (n*SUM(XY) - SUM(X)*SUM(Y)) /
    --                  SQRT((n*SUM(X2)-SUM(X)^2) * (n*SUM(Y2)-SUM(Y)^2))
    INSERT INTO paloalto_client.rpt_correlation
        (period_months, ticker, variance, risk, corr_vs_spy, corr_vs_agg, corr_vs_vt, executed_at)
    SELECT
        p_months,
        r.ticker,
        POW(STD(r.ror), 2) AS variance,
        STD(r.ror)         AS risk,
        (COUNT(*) * SUM(r.ror * spy.ror) - SUM(r.ror) * SUM(spy.ror)) /
        NULLIF(SQRT(
            (COUNT(*) * SUM(r.ror * r.ror)    - POW(SUM(r.ror),   2)) *
            (COUNT(*) * SUM(spy.ror * spy.ror) - POW(SUM(spy.ror), 2))
        ), 0) AS corr_vs_spy,
        (COUNT(*) * SUM(r.ror * agg.ror) - SUM(r.ror) * SUM(agg.ror)) /
        NULLIF(SQRT(
            (COUNT(*) * SUM(r.ror * r.ror)    - POW(SUM(r.ror),   2)) *
            (COUNT(*) * SUM(agg.ror * agg.ror) - POW(SUM(agg.ror), 2))
        ), 0) AS corr_vs_agg,
        (COUNT(*) * SUM(r.ror * vt.ror) - SUM(r.ror) * SUM(vt.ror)) /
        NULLIF(SQRT(
            (COUNT(*) * SUM(r.ror * r.ror)   - POW(SUM(r.ror),  2)) *
            (COUNT(*) * SUM(vt.ror * vt.ror)  - POW(SUM(vt.ror), 2))
        ), 0) AS corr_vs_vt,
        v_now
    FROM paloalto_client.fct_daily_ror r
    JOIN paloalto_client.fct_daily_ror spy ON r.date = spy.date AND spy.ticker = 'SPY'
    JOIN paloalto_client.fct_daily_ror agg ON r.date = agg.date AND agg.ticker = 'AGG'
    JOIN paloalto_client.fct_daily_ror vt  ON r.date = vt.date  AND vt.ticker  = 'VT'
    WHERE r.date  >= v_start_date
      AND r.ror   IS NOT NULL
      AND spy.ror IS NOT NULL
      AND agg.ror IS NOT NULL
      AND vt.ror  IS NOT NULL
    GROUP BY r.ticker;

    SELECT CONCAT('sp_correlation completed for ', p_months, 'M') AS status,
           v_start_date AS period_start, v_end_date AS period_end;

    SELECT
        c.period_months,
        c.ticker,
        t.asset_class,
        CASE WHEN t.is_benchmark = 1 THEN 'Benchmark' ELSE 'Portfolio' END AS ticker_type,
        ROUND(c.risk         * 100,   4) AS risk_pct,
        ROUND(c.variance     * 10000, 6) AS variance_x10000,
        ROUND(c.corr_vs_spy, 4)          AS corr_vs_spy,
        ROUND(c.corr_vs_agg, 4)          AS corr_vs_agg,
        ROUND(c.corr_vs_vt,  4)          AS corr_vs_vt
    FROM paloalto_client.rpt_correlation c
    JOIN paloalto_client.dim_ticker t ON c.ticker = t.ticker
    WHERE c.period_months = p_months
    ORDER BY t.is_benchmark, c.variance ASC;

END$$
DELIMITER ;


/* -----------------------------------------------------------------------------------------
   STEP 4: sp_rebalanced_portfolio(p_months INT)

   Answers assignment questions 4 and 5.

   Before running this procedure you must:
   1. Run sp_portfolio_analysis for the same period
   2. Review the results and decide which tickers to include in the new portfolio
   3. Update dim_rebalanced_weights:
      UPDATE paloalto_client.dim_rebalanced_weights
      SET include_in_rebalance = 1
      WHERE ticker IN ('IXN', 'QQQ', 'GLD', 'SPY');  -- example

   The procedure then:
   - Reads tickers where include_in_rebalance = 1
   - Calculates new weights using Sharpe-proportional method:
     new_weight = sharpe_ticker / SUM(sharpe_all_selected_tickers)
   - Higher Sharpe = higher recommended weight
   - Saves new weights to dim_rebalanced_weights
   - Calculates new portfolio metrics with the new weights
   - Shows before vs after comparison on screen
----------------------------------------------------------------------------------------- */

/* -----------------------------------------------------------------------------------------
   Rebalancing: sp_rebalanced_portfolio(p_months INT)
 
 Before running this procedure you must:
   1. Run sp_portfolio_analysis for the same period
   2. Review the results and decide which tickers to include in the new portfolio
   3. Update dim_rebalanced_weights, before call the sp_rebalanced_portfolio:
----------------------------------------------------------------------------------------- */
UPDATE paloalto_client.dim_rebalanced_weights
SET include_in_rebalance = 1
WHERE ticker IN ('IXN', 'QQQ', 'GLD', 'SPY');  
      
DROP PROCEDURE IF EXISTS paloalto_client.sp_rebalanced_portfolio;

DELIMITER $$
CREATE PROCEDURE paloalto_client.sp_rebalanced_portfolio(IN p_months INT)
BEGIN
    DECLARE v_now DATETIME DEFAULT NOW();
    -- clean previous rebalanced results for this period
    DELETE FROM paloalto_client.rpt_portfolio_summary
    WHERE period_months = p_months AND is_rebalanced = 1;

    -- calculate new weights using Sharpe-proportional method
    -- new_weight = sharpe / SUM(sharpe of all selected tickers)
    -- tickers with higher risk-adjusted return get more weight
    UPDATE paloalto_client.dim_rebalanced_weights w
    JOIN (
        SELECT
            s.ticker,
            s.sharpe_ratio / SUM(s.sharpe_ratio) OVER() AS new_pct,
            h.allocation_pct                             AS current_pct,
            (s.sharpe_ratio / SUM(s.sharpe_ratio) OVER()) - IFNULL(h.allocation_pct, 0) AS change_pct
        FROM paloalto_client.rpt_stats s
        JOIN paloalto_client.dim_rebalanced_weights drw ON s.ticker = drw.ticker
        LEFT JOIN paloalto_client.fct_holdings h ON s.ticker = h.ticker
        WHERE s.period_months = p_months
          AND drw.include_in_rebalance = 1
          AND s.sharpe_ratio > 0
    ) calc ON w.ticker = calc.ticker
    SET
        w.new_pct     = calc.new_pct,
        w.change_pct  = calc.change_pct,
        w.method      = 'sharpe_proportional',
        w.executed_at = v_now;

    -- calculate rebalanced portfolio metrics
    INSERT INTO paloalto_client.rpt_portfolio_summary
        (period_months, is_rebalanced,
         portfolio_expected_ror, portfolio_risk, portfolio_sharpe,
         as_of_date, executed_at)
    SELECT
        p_months,
        1,
        SUM(s.expected_ror  * w.new_pct),
        SUM(s.risk          * w.new_pct),
        SUM(s.sharpe_ratio  * w.new_pct),
        MAX(s.period_end),
        v_now
    FROM paloalto_client.rpt_stats s
    JOIN paloalto_client.dim_rebalanced_weights w ON s.ticker = w.ticker
    WHERE s.period_months = p_months
      AND w.include_in_rebalance = 1
      AND w.new_pct IS NOT NULL;

    SELECT CONCAT('sp_rebalanced_portfolio completed for ', p_months, 'M') AS status, v_now;
    -- show new weights
    SELECT
        w.ticker,
        t.asset_class,
        ROUND(IFNULL(h.allocation_pct, 0) * 100, 2) AS current_weight_pct,
        ROUND(w.new_pct    * 100, 2)                 AS new_weight_pct,
        ROUND(w.change_pct * 100, 2)                 AS change_pct,
        CASE
            WHEN IFNULL(h.allocation_pct, 0) = 0     THEN 'ADD'
            WHEN w.change_pct >  0.005                THEN 'INCREASE'
            WHEN w.change_pct < -0.005                THEN 'REDUCE'
            ELSE 'HOLD'
        END AS action,
        w.method
    FROM paloalto_client.dim_rebalanced_weights w
    JOIN paloalto_client.dim_ticker t ON w.ticker = t.ticker
    LEFT JOIN paloalto_client.fct_holdings h ON w.ticker = h.ticker
    WHERE w.include_in_rebalance = 1
    ORDER BY w.new_pct DESC;

    -- before vs after comparison
    SELECT
        period_months,
        CASE WHEN is_rebalanced = 0 THEN 'Current Portfolio'
             ELSE 'Rebalanced Portfolio' END     AS portfolio_version,
        ROUND(portfolio_expected_ror * 100, 4)   AS expected_ror_pct,
        ROUND(portfolio_risk         * 100, 4)   AS risk_pct,
        ROUND(portfolio_sharpe,      4)           AS sharpe_ratio
    FROM paloalto_client.rpt_portfolio_summary
    WHERE period_months = p_months
    ORDER BY is_rebalanced;
END$$
DELIMITER ;
