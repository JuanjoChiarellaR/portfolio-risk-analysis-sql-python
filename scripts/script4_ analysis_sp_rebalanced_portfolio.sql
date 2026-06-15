/* ---------------------------------------------------------------------------------
   Rebalancing: sp_rebalanced_portfolio(p_months INT)
 
 Before running this procedure you must:
   1. Run sp_portfolio_analysis for the same period
   2. Review the results and decide which tickers to include in the new portfolio
   3. Update dim_rebalanced_weights, before call the sp_rebalanced_portfolio:
--------------------------------------------------------------------------------- */

-- Update dim_rebalanced_weights with selected tickers
UPDATE paloalto_client.dim_rebalanced_weights
SET include_in_rebalance = 1
WHERE ticker IN ('IXN', 'QQQ', 'GLD', 'VNQ', 'VT', 'AGG');

UPDATE paloalto_client.dim_rebalanced_weights
SET include_in_rebalance = 0
WHERE ticker IN ('IEF', 'SPY');

-- Verify
SELECT * FROM paloalto_client.dim_rebalanced_weights;

-- Call sp_rebalanced_portfolio for all periods
CALL paloalto_client.sp_rebalanced_portfolio(12);
CALL paloalto_client.sp_rebalanced_portfolio(18);
CALL paloalto_client.sp_rebalanced_portfolio(24);

SELECT
    period_months,
    CASE WHEN is_rebalanced = 0 
         THEN 'Current Portfolio'
         ELSE 'Rebalanced Portfolio' 
    END                                        AS portfolio_version,
    ROUND(portfolio_expected_ror * 100, 4)     AS return_pct,
    ROUND(portfolio_risk         * 100, 4)     AS risk_pct,
    ROUND(portfolio_sharpe,            4)      AS sharpe_ratio,
    as_of_date
FROM paloalto_client.rpt_portfolio_summary
ORDER BY period_months, is_rebalanced;

