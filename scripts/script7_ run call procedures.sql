-- STEP 1: Run portfolio analysis for all periods
CALL paloalto_client.sp_portfolio_analysis(12);
CALL paloalto_client.sp_portfolio_analysis(18);
CALL paloalto_client.sp_portfolio_analysis(24);

-- STEP 2: Run correlation vs benchmarks for all periods
CALL paloalto_client.sp_correlation(12);
CALL paloalto_client.sp_correlation(18);
CALL paloalto_client.sp_correlation(24);

-- STEP 3: Run internal correlation matrix for all periods
CALL paloalto_client.sp_correlation_matrix(12);
CALL paloalto_client.sp_correlation_matrix(18);
CALL paloalto_client.sp_correlation_matrix(24);

-- STEP 4: Update rebalancing selection
UPDATE paloalto_client.dim_rebalanced_weights
SET include_in_rebalance = 1
WHERE ticker IN ('IXN', 'QQQ', 'GLD', 'VNQ', 'VT', 'AGG');

UPDATE paloalto_client.dim_rebalanced_weights
SET include_in_rebalance = 0
WHERE ticker IN ('IEF', 'SPY');

-- STEP 5: Run rebalanced portfolio for all periods
CALL paloalto_client.sp_rebalanced_portfolio(12);
CALL paloalto_client.sp_rebalanced_portfolio(18);
CALL paloalto_client.sp_rebalanced_portfolio(24);

