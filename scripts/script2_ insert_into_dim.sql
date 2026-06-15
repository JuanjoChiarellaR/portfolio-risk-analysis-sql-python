/* =========================================================================================
   SCRIPT 2 - INSERT DIM AND FACT DATA
   Client:   Palo Alto UHNW Client
   Schema:   paloalto_client
   Date:     June 2026
   Run this AFTER script1.
   fct_pricing_daily is loaded separately using data/pricing_inserts.sql.
========================================================================================= */

/* -----------------------------------------------------------------------------------------
   dim_client
----------------------------------------------------------------------------------------- */
INSERT INTO paloalto_client.dim_client (full_name, location, total_aum_usd)
VALUES ('Juanjo Chiarella', 'Palo Alto, CA', 95000000.00);
/* -----------------------------------------------------------------------------------------
   dim_ticker
   5 portfolio holdings + 3 benchmarks.
   SPY = US equity benchmark
   AGG = US fixed income benchmark (natural reference for IEF)
   VT  = Global equity benchmark (relevant because IXN is global tech)
----------------------------------------------------------------------------------------- */
-- portfolio holdings
INSERT INTO paloalto_client.dim_ticker (ticker, ticker_name, asset_class, is_benchmark)
VALUES ('IXN', 'iShares Global Tech ETF',             'Equity',       0);
INSERT INTO paloalto_client.dim_ticker (ticker, ticker_name, asset_class, is_benchmark)
VALUES ('QQQ', 'Invesco NASDAQ 100 ETF',              'Equity',       0);
INSERT INTO paloalto_client.dim_ticker (ticker, ticker_name, asset_class, is_benchmark)
VALUES ('IEF', 'iShares 7-10 Year Treasury Bond ETF', 'Fixed Income', 0);
INSERT INTO paloalto_client.dim_ticker (ticker, ticker_name, asset_class, is_benchmark)
VALUES ('VNQ', 'Vanguard Real Estate ETF',            'Real Assets',  0);
INSERT INTO paloalto_client.dim_ticker (ticker, ticker_name, asset_class, is_benchmark)
VALUES ('GLD', 'SPDR Gold Shares',                    'Commodities',  0);
-- benchmarks
INSERT INTO paloalto_client.dim_ticker (ticker, ticker_name, asset_class, is_benchmark)
VALUES ('SPY', 'SPDR S&P 500 ETF',                   'Equity',       1);
INSERT INTO paloalto_client.dim_ticker (ticker, ticker_name, asset_class, is_benchmark)
VALUES ('AGG', 'iShares Core US Aggregate Bond ETF',  'Fixed Income', 1);
INSERT INTO paloalto_client.dim_ticker (ticker, ticker_name, asset_class, is_benchmark)
VALUES ('VT',  'Vanguard Total World Stock ETF',      'Equity',       1);

/* -----------------------------------------------------------------------------------------
   fct_holdings
   allocation_pct stored as decimal: 0.1750 = 17.5%
   value_usd = allocation_pct x 95,000,000
----------------------------------------------------------------------------------------- */
INSERT INTO paloalto_client.fct_holdings (customer_id, ticker, allocation_pct, value_usd)
VALUES (1, 'IXN', 0.1750, 16625000.00);
INSERT INTO paloalto_client.fct_holdings (customer_id, ticker, allocation_pct, value_usd)
VALUES (1, 'QQQ', 0.2210, 20995000.00);
INSERT INTO paloalto_client.fct_holdings (customer_id, ticker, allocation_pct, value_usd)
VALUES (1, 'IEF', 0.2850, 27075000.00);
INSERT INTO paloalto_client.fct_holdings (customer_id, ticker, allocation_pct, value_usd)
VALUES (1, 'VNQ', 0.0890,  8455000.00);
INSERT INTO paloalto_client.fct_holdings (customer_id, ticker, allocation_pct, value_usd)
VALUES (1, 'GLD', 0.2300, 21850000.00);
/* -----------------------------------------------------------------------------------------
   dim_rebalanced_weights
   Pre-filled with all 8 tickers and include_in_rebalance = 0.
   After running sp_portfolio_analysis and sp_correlation and reviewing the results,
   you update include_in_rebalance = 1 for the tickers you want in the new portfolio.
   sp_rebalanced_portfolio then calculates the new weights using Sharpe-proportional method.
----------------------------------------------------------------------------------------- */
INSERT INTO paloalto_client.dim_rebalanced_weights (ticker, include_in_rebalance)
VALUES ('IXN', 0);
INSERT INTO paloalto_client.dim_rebalanced_weights (ticker, include_in_rebalance)
VALUES ('QQQ', 0);
INSERT INTO paloalto_client.dim_rebalanced_weights (ticker, include_in_rebalance)
VALUES ('IEF', 0);
INSERT INTO paloalto_client.dim_rebalanced_weights (ticker, include_in_rebalance)
VALUES ('VNQ', 0);
INSERT INTO paloalto_client.dim_rebalanced_weights (ticker, include_in_rebalance)
VALUES ('GLD', 0);
INSERT INTO paloalto_client.dim_rebalanced_weights (ticker, include_in_rebalance)
VALUES ('SPY', 0);
INSERT INTO paloalto_client.dim_rebalanced_weights (ticker, include_in_rebalance)
VALUES ('AGG', 0);
INSERT INTO paloalto_client.dim_rebalanced_weights (ticker, include_in_rebalance)
VALUES ('VT',  0);



/* =========================================================================================
   VALIDATION
========================================================================================= */

-- verify client
SELECT * FROM paloalto_client.dim_client;

-- verify all 8 tickers
SELECT ticker, ticker_name, asset_class,
       CASE WHEN is_benchmark = 1 THEN 'Benchmark' ELSE 'Portfolio' END AS ticker_type
FROM paloalto_client.dim_ticker
ORDER BY is_benchmark, asset_class;

-- verify holdings add up to 100% and $95M
SELECT
    COUNT(*)               AS num_holdings,
    SUM(allocation_pct)    AS total_allocation,
    SUM(value_usd)         AS total_value_usd
FROM paloalto_client.fct_holdings;

-- verify dim_rebalanced_weights pre-filled
SELECT * FROM paloalto_client.dim_rebalanced_weights;
