/* =========================================================================================
   SCRIPT 6 - SP_CORRELATION_MATRIX
   Client:   Palo Alto UHNW Client
   Schema:   paloalto_client
   Author:   Juanjo Chiarella
   Course:   Data Management & SQL - DAT 5486
   Date:     June 2026

   Stored procedure that calculates the Pearson correlation between each pair
   of portfolio holdings (IXN, QQQ, IEF, VNQ, GLD) for a given time window.

   Input parameter: p_months INT (12, 18, or 24)

   Same Pearson formula used in sp_correlation:
   corr(X,Y) = (n*SUM(XY) - SUM(X)*SUM(Y)) /
               SQRT((n*SUM(X2)-SUM(X)^2) * (n*SUM(Y2)-SUM(Y)^2))

   Output: rpt_correlation_matrix
   Values close to 1.0 = move together (low diversification benefit)
   Values close to 0   = independent
   Negative values     = move in opposite directions
========================================================================================= */

USE paloalto_client;


/* -----------------------------------------------------------------------------------------
   Create the report table if it does not exist
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
   Drop and recreate the procedure
----------------------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS paloalto_client.sp_correlation_matrix;

DELIMITER $$
CREATE PROCEDURE paloalto_client.sp_correlation_matrix(IN p_months INT)
BEGIN
    DECLARE v_start_date DATE;
    
    -- Calculate start date from the most recent date in the pricing table
    SELECT DATE_SUB(MAX(date), INTERVAL p_months MONTH)
    INTO   v_start_date
    FROM   paloalto_client.fct_pricing_daily;

    -- Clear previous results for this period
    DELETE FROM paloalto_client.rpt_correlation_matrix
    WHERE period_months = p_months;

    -- Calculate Pearson correlation for all pairs of portfolio holdings
    INSERT INTO paloalto_client.rpt_correlation_matrix
        (period_months, ticker_a, ticker_b, correlation, executed_at)
    SELECT
        p_months                AS period_months,
        a.ticker                AS ticker_a,
        b.ticker                AS ticker_b,
        (COUNT(*) * SUM(a.ror * b.ror) - SUM(a.ror) * SUM(b.ror)) /
        NULLIF(SQRT(
            (COUNT(*) * SUM(a.ror * a.ror) - POW(SUM(a.ror), 2)) *
            (COUNT(*) * SUM(b.ror * b.ror) - POW(SUM(b.ror), 2))
        ), 0)                   AS correlation,
        NOW()                   AS executed_at
    FROM paloalto_client.fct_daily_ror a
    JOIN paloalto_client.fct_daily_ror b ON a.date = b.date
    WHERE a.ticker IN ('IXN', 'QQQ', 'IEF', 'VNQ', 'GLD')
      AND b.ticker IN ('IXN', 'QQQ', 'IEF', 'VNQ', 'GLD')
      AND a.date >= v_start_date
      AND a.ror IS NOT NULL
      AND b.ror IS NOT NULL
    GROUP BY a.ticker, b.ticker;

    -- Return the correlation matrix as a pivot
    SELECT
        ticker_a                                                          AS Ticker,
        ROUND(MAX(CASE WHEN ticker_b = 'IXN' THEN correlation END), 4)   AS IXN,
        ROUND(MAX(CASE WHEN ticker_b = 'QQQ' THEN correlation END), 4)   AS QQQ,
        ROUND(MAX(CASE WHEN ticker_b = 'IEF' THEN correlation END), 4)   AS IEF,
        ROUND(MAX(CASE WHEN ticker_b = 'VNQ' THEN correlation END), 4)   AS VNQ,
        ROUND(MAX(CASE WHEN ticker_b = 'GLD' THEN correlation END), 4)   AS GLD
    FROM paloalto_client.rpt_correlation_matrix
    WHERE period_months = p_months
    GROUP BY ticker_a
    ORDER BY FIELD(ticker_a, 'IXN', 'QQQ', 'IEF', 'VNQ', 'GLD');
END$$
DELIMITER ;


/* -----------------------------------------------------------------------------------------
   CALL THE PROCEDURE
   Run for the 12-month period as used in the analysis.
----------------------------------------------------------------------------------------- */
CALL paloalto_client.sp_correlation_matrix(12);
