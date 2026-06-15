/* =========================================================================================
   SCRIPT 5 - REPORTS AND REBALANCING
   Client:   Palo Alto UHNW Client
   Schema:   paloalto_client
   Author:   Juanjo Chiarella
   Course:   Data Management & SQL - DAT 5486
   Date:     June 2026

   Run this AFTER script4 and after calling all procedures.

   Order of execution:
   1. Call sp_portfolio_analysis for all periods
   2. Call sp_correlation for all periods
   3. Review results and decide which tickers to include in rebalanced portfolio
   4. Update dim_rebalanced_weights with your selection
   5. Call sp_rebalanced_portfolio
   6. Run the SELECT reports below
========================================================================================= */

USE paloalto_client;


/* -----------------------------------------------------------------------------------------
   CALL ALL PROCEDURES
   Run sp_portfolio_analysis and sp_correlation for all 3 periods first.
   Review the results, then update dim_rebalanced_weights and run sp_rebalanced_portfolio.
----------------------------------------------------------------------------------------- */

CALL paloalto_client.sp_portfolio_analysis(12);
CALL paloalto_client.sp_portfolio_analysis(18);
CALL paloalto_client.sp_portfolio_analysis(24);

CALL paloalto_client.sp_correlation(12);
CALL paloalto_client.sp_correlation(18);
CALL paloalto_client.sp_correlation(24);


/* -----------------------------------------------------------------------------------------
   REBALANCING — update this section after reviewing the results above.

   Set include_in_rebalance = 1 for the tickers you want in the new portfolio.
   You can include benchmarks (SPY, AGG, VT) if you want to add them as new holdings.
   Tickers with include_in_rebalance = 0 are excluded from the rebalanced portfolio.

   Example — uncomment and modify after your analysis:
   UPDATE paloalto_client.dim_rebalanced_weights
   SET include_in_rebalance = 1
   WHERE ticker IN ('IXN', 'QQQ', 'GLD', 'SPY');

   Then run:
   CALL paloalto_client.sp_rebalanced_portfolio(12);
   CALL paloalto_client.sp_rebalanced_portfolio(18);
   CALL paloalto_client.sp_rebalanced_portfolio(24);
----------------------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------------------
   QUESTION 1 & 3 — Return and risk per ticker across all periods
----------------------------------------------------------------------------------------- */
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
ORDER BY s.period_months, t.is_benchmark, s.sharpe_ratio DESC;


/* -----------------------------------------------------------------------------------------
   QUESTION 1 & 3 — Weighted portfolio summary across all periods
----------------------------------------------------------------------------------------- */
SELECT
    period_months,
    ROUND(portfolio_expected_ror * 100, 4) AS portfolio_expected_ror_pct,
    ROUND(portfolio_risk         * 100, 4) AS portfolio_risk_pct,
    ROUND(portfolio_sharpe,      4)        AS portfolio_sharpe,
    as_of_date
FROM paloalto_client.rpt_portfolio_summary
WHERE is_rebalanced = 0
ORDER BY period_months;


/* -----------------------------------------------------------------------------------------
   QUESTION 2 — Correlation and variance across all periods
----------------------------------------------------------------------------------------- */
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
ORDER BY c.period_months, t.is_benchmark, c.variance ASC;


/* -----------------------------------------------------------------------------------------
   QUESTION 4 & 5 — Rebalanced weights and before vs after comparison
----------------------------------------------------------------------------------------- */
SELECT
    w.ticker,
    t.asset_class,
    ROUND(IFNULL(h.allocation_pct, 0) * 100, 2) AS current_weight_pct,
    ROUND(w.new_pct    * 100, 2)                 AS new_weight_pct,
    ROUND(w.change_pct * 100, 2)                 AS change_pct,
    CASE
        WHEN IFNULL(h.allocation_pct, 0) = 0 THEN 'ADD'
        WHEN w.change_pct >  0.005            THEN 'INCREASE'
        WHEN w.change_pct < -0.005            THEN 'REDUCE'
        ELSE 'HOLD'
    END AS action
FROM paloalto_client.dim_rebalanced_weights w
JOIN paloalto_client.dim_ticker t ON w.ticker = t.ticker
LEFT JOIN paloalto_client.fct_holdings h ON w.ticker = h.ticker
WHERE w.include_in_rebalance = 1
ORDER BY w.new_pct DESC;

SELECT
    period_months,
    CASE WHEN is_rebalanced = 0 THEN 'Current Portfolio'
         ELSE 'Rebalanced Portfolio' END     AS portfolio_version,
    ROUND(portfolio_expected_ror * 100, 4)   AS expected_ror_pct,
    ROUND(portfolio_risk         * 100, 4)   AS risk_pct,
    ROUND(portfolio_sharpe,      4)          AS sharpe_ratio,
    as_of_date
FROM paloalto_client.rpt_portfolio_summary
ORDER BY period_months, is_rebalanced;
