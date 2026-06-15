-- Query 1: rpt_stats completo
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

-- Query 2: correlaciones completo
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

-- Query 3: portfolio summary current vs rebalanced
SELECT
    period_months,
    CASE WHEN is_rebalanced = 0 THEN 'Current Portfolio'
         ELSE 'Rebalanced Portfolio' END AS portfolio_version,
    ROUND(portfolio_expected_ror * 100, 4) AS expected_ror_pct,
    ROUND(portfolio_risk         * 100, 4) AS risk_pct,
    ROUND(portfolio_sharpe,      4)        AS sharpe_ratio,
    as_of_date
FROM paloalto_client.rpt_portfolio_summary
ORDER BY period_months, is_rebalanced;

-- Query 4: rebalanced weights
SELECT
    w.ticker,
    t.ticker_name,
    t.asset_class,
    ROUND(IFNULL(h.allocation_pct, 0) * 100, 2) AS current_weight_pct,
    ROUND(IFNULL(w.new_pct, 0)        * 100, 2) AS new_weight_pct,
    CASE
        WHEN w.include_in_rebalance = 0           THEN 'REMOVE'
        WHEN IFNULL(h.allocation_pct, 0) = 0      THEN 'ADD'
        WHEN w.change_pct >  0.005                THEN 'INCREASE'
        WHEN w.change_pct < -0.005                THEN 'REDUCE'
        ELSE 'HOLD'
    END AS action
FROM paloalto_client.dim_rebalanced_weights w
JOIN paloalto_client.dim_ticker t ON w.ticker = t.ticker
LEFT JOIN paloalto_client.fct_holdings h ON w.ticker = h.ticker
ORDER BY w.include_in_rebalance DESC, IFNULL(w.new_pct, 0) DESC;