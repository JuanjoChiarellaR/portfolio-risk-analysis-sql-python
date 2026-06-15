/* =========================================================================================
   SCRIPT 4 - REPORTS
   Client:   Palo Alto UHNW Client
   Schema:   paloalto_client
   Author:   Juanjo Chiarella
   Course:   Data Management & SQL - DAT 5486
   Date:     June 2026

   Run the three procedures first, then use these SELECT queries to read all results.
   Each procedure already shows results on screen when called.
   These queries let you compare all periods side by side.

   Execution order:
       CALL paloalto_client.sp_portfolio_analysis(12);
       CALL paloalto_client.sp_portfolio_analysis(18);
       CALL paloalto_client.sp_portfolio_analysis(24);
       CALL paloalto_client.sp_correlation(12);
       CALL paloalto_client.sp_correlation(18);
       CALL paloalto_client.sp_correlation(24);
       CALL paloalto_client.sp_rebalanced_portfolio(12);
       CALL paloalto_client.sp_rebalanced_portfolio(18);
       CALL paloalto_client.sp_rebalanced_portfolio(24);
========================================================================================= */

USE paloalto_client;


/* -----------------------------------------------------------------------------------------
   QUESTION 1 & 3 — Return and risk per ticker across all periods
   Shows total return, expected daily return, risk and Sharpe side by side
   for 12M, 18M and 24M so we can compare trends over time.
----------------------------------------------------------------------------------------- */
SELECT
    s.period_months,
    s.ticker,
    t.asset_class,
    CASE WHEN t.is_benchmark = 1 THEN 'Benchmark' ELSE 'Portfolio' END AS ticker_type,
    ROUND(s.total_return   * 100, 2) AS total_return_pct,
    ROUND(s.expected_ror   * 100, 4) AS expected_daily_ror_pct,
    ROUND(s.risk           * 100, 4) AS risk_pct,
    ROUND(s.sharpe_ratio,  4)        AS sharpe_ratio,
    s.period_start,
    s.period_end
FROM paloalto_client.rpt_stats s
JOIN paloalto_client.dim_ticker t ON s.ticker = t.ticker
ORDER BY s.period_months, t.is_benchmark, s.sharpe_ratio DESC;


/* -----------------------------------------------------------------------------------------
   QUESTION 1 & 3 — Portfolio summary across all periods (current weights only)
----------------------------------------------------------------------------------------- */
SELECT
    period_months,
    ROUND(portfolio_total_return   * 100, 2) AS total_return_pct,
    ROUND(portfolio_expected_ror   * 100, 4) AS expected_daily_ror_pct,
    ROUND(portfolio_risk           * 100, 4) AS risk_pct,
    ROUND(portfolio_sharpe,        4)        AS sharpe_ratio,
    as_of_date
FROM paloalto_client.rpt_portfolio_summary
WHERE is_rebalanced = 0
ORDER BY period_months;


/* -----------------------------------------------------------------------------------------
   QUESTION 2 — Correlation and variance across all periods
   Lower variance = more stable asset.
   Correlation close to 1 = moves with the benchmark.
   Correlation close to 0 = independent from the benchmark.
   Negative correlation = moves opposite to the benchmark (good for diversification).
----------------------------------------------------------------------------------------- */
SELECT
    c.period_months,
    c.ticker,
    t.asset_class,
    CASE WHEN t.is_benchmark = 1 THEN 'Benchmark' ELSE 'Portfolio' END AS ticker_type,
    ROUND(c.risk      * 100,  4)  AS risk_pct,
    ROUND(c.variance  * 10000, 6) AS variance_x10000,
    ROUND(c.corr_vs_spy, 4)       AS corr_vs_spy,
    ROUND(c.corr_vs_agg, 4)       AS corr_vs_agg,
    ROUND(c.corr_vs_vt,  4)       AS corr_vs_vt
FROM paloalto_client.rpt_correlation c
JOIN paloalto_client.dim_ticker t ON c.ticker = t.ticker
ORDER BY c.period_months, t.is_benchmark, c.variance ASC;


/* -----------------------------------------------------------------------------------------
   QUESTION 4 & 5 — Rebalanced weights and before vs after comparison
----------------------------------------------------------------------------------------- */

-- new weights recommended by inverse volatility method
SELECT
    w.period_months,
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
ORDER BY w.period_months, w.new_pct DESC;

-- before vs after portfolio comparison across all periods
SELECT
    period_months,
    CASE WHEN is_rebalanced = 0 THEN 'Current Portfolio'
         ELSE 'Rebalanced Portfolio' END              AS portfolio_version,
    ROUND(portfolio_total_return   * 100, 2)          AS total_return_pct,
    ROUND(portfolio_expected_ror   * 100, 4)          AS expected_daily_ror_pct,
    ROUND(portfolio_risk           * 100, 4)          AS risk_pct,
    ROUND(portfolio_sharpe,        4)                 AS sharpe_ratio,
    as_of_date
FROM paloalto_client.rpt_portfolio_summary
ORDER BY period_months, is_rebalanced;
