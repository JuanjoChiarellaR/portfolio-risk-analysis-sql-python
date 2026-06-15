/* =========================================================================================
   SCRIPT 6 - PORTFOLIO CORRELATION MATRIX
   Client:   Palo Alto UHNW Client
   Schema:   paloalto_client
   Author:   Juanjo Chiarella
   Course:   Data Management & SQL - DAT 5486
   Date:     June 2026

   This script calculates the Pearson correlation between each pair of portfolio
   holdings (IXN, QQQ, IEF, VNQ, GLD) for the most recent 12-month period.

   It uses the same Pearson formula already implemented in sp_correlation:
   corr(X,Y) = (n*SUM(XY) - SUM(X)*SUM(Y)) /
               SQRT((n*SUM(X2)-SUM(X)^2) * (n*SUM(Y2)-SUM(Y)^2))

   Output: a 5x5 matrix showing how each holding moves relative to the others.
   Values close to 1.0 = move together (low diversification benefit).
   Values close to 0   = independent.
   Negative values     = move in opposite directions (good hedge).
========================================================================================= */

USE paloalto_client;

/* -----------------------------------------------------------------------------------------
   STEP 1: Create the report table if it does not exist
----------------------------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS paloalto_client.rpt_correlation_matrix (
    period_months  INT          NOT NULL,
    ticker_a       VARCHAR(10)  NOT NULL,
    ticker_b       VARCHAR(10)  NOT NULL,
    correlation    DECIMAL(10,6),
    executed_at    DATETIME     NOT NULL,
    PRIMARY KEY (period_months, ticker_a, ticker_b)
);

/* -----------------------------------------------------------------------------------------
   STEP 2: Clear previous results for 12M
----------------------------------------------------------------------------------------- */
DELETE FROM paloalto_client.rpt_correlation_matrix
WHERE period_months = 12;

/* -----------------------------------------------------------------------------------------
   STEP 3: Calculate Pearson correlation for all pairs of portfolio holdings
   Period: most recent 12 months
   Tickers: IXN, QQQ, IEF, VNQ, GLD (portfolio holdings only, no benchmarks)
----------------------------------------------------------------------------------------- */
INSERT INTO paloalto_client.rpt_correlation_matrix
    (period_months, ticker_a, ticker_b, correlation, executed_at)
SELECT
    12                    AS period_months,
    a.ticker              AS ticker_a,
    b.ticker              AS ticker_b,
    (COUNT(*) * SUM(a.ror * b.ror) - SUM(a.ror) * SUM(b.ror)) /
    NULLIF(SQRT(
        (COUNT(*) * SUM(a.ror * a.ror) - POW(SUM(a.ror), 2)) *
        (COUNT(*) * SUM(b.ror * b.ror) - POW(SUM(b.ror), 2))
    ), 0)                 AS correlation,
    NOW()                 AS executed_at
FROM paloalto_client.fct_daily_ror a
JOIN paloalto_client.fct_daily_ror b ON a.date = b.date
WHERE a.ticker IN ('IXN', 'QQQ', 'IEF', 'VNQ', 'GLD')
  AND b.ticker IN ('IXN', 'QQQ', 'IEF', 'VNQ', 'GLD')
  AND a.date >= DATE_SUB(
        (SELECT MAX(date) FROM paloalto_client.fct_pricing_daily),
        INTERVAL 12 MONTH
      )
  AND a.ror IS NOT NULL
  AND b.ror IS NOT NULL
GROUP BY a.ticker, b.ticker;

/* -----------------------------------------------------------------------------------------
   STEP 4: Show the correlation matrix as a pivot
   Rows = ticker_a, Columns = IXN / QQQ / IEF / VNQ / GLD
----------------------------------------------------------------------------------------- */
SELECT
    ticker_a                                                          AS Ticker,
    ROUND(MAX(CASE WHEN ticker_b = 'IXN' THEN correlation END), 4)   AS IXN,
    ROUND(MAX(CASE WHEN ticker_b = 'QQQ' THEN correlation END), 4)   AS QQQ,
    ROUND(MAX(CASE WHEN ticker_b = 'IEF' THEN correlation END), 4)   AS IEF,
    ROUND(MAX(CASE WHEN ticker_b = 'VNQ' THEN correlation END), 4)   AS VNQ,
    ROUND(MAX(CASE WHEN ticker_b = 'GLD' THEN correlation END), 4)   AS GLD
FROM paloalto_client.rpt_correlation_matrix
WHERE period_months = 12
GROUP BY ticker_a
ORDER BY FIELD(ticker_a, 'IXN', 'QQQ', 'IEF', 'VNQ', 'GLD');

