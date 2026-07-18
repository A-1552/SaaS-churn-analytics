/* SaaS Customer Churn & Revenue Risk Analytics
Tools - 
- MySQL 8
- Excel
- Power BI

Key SQL Concepts - 
- Joins
- Aggregate Functions
- CASE Statements
- Views
- Window Functions
- Business KPI Calculations
*/

CREATE DATABASE ravenstack;
USE ravenstack;


SELECT COUNT(*) FROM ravenstack_accounts;
SELECT COUNT(*) FROM ravenstack_subscriptions;
SELECT COUNT(*) FROM ravenstack_feature_usage;
SELECT COUNT(*) FROM ravenstack_support_tickets;
SELECT COUNT(*) FROM ravenstack_churn_events;


-- Total number of churned accounts
SELECT COUNT(DISTINCT account_id) AS ravenstack_churned_accounts
FROM ravenstack_churn_events;

-- Overall churn rate (%)
SELECT
    ROUND(
        COUNT(DISTINCT c.account_id) * 100.0 /
        COUNT(DISTINCT a.account_id),
        2
    ) AS churn_rate
FROM ravenstack_accounts a
LEFT JOIN ravenstack_churn_events c
    ON a.account_id = c.account_id;

-- Total MRR (Monthly Recurring Revenue)
SELECT ROUND(SUM(mrr_amount), 2) AS total_mrr
FROM ravenstack_subscriptions;

-- Total ARR (Annual Recurring Revenue)
SELECT ROUND(SUM(arr_amount), 2) AS total_arr
FROM ravenstack_subscriptions;


/* SECTION 3: SEGMENTATION — INDUSTRY & PLAN TIER */

-- Customer count by industry
SELECT
    industry,
    COUNT(*) AS accounts
FROM ravenstack_accounts
GROUP BY industry
ORDER BY accounts DESC;

-- Customer count by plan tier
SELECT
    plan_tier,
    COUNT(*) AS customers
FROM ravenstack_accounts
GROUP BY plan_tier;

-- MRR by plan tier
SELECT
    plan_tier,
    ROUND(SUM(mrr_amount), 2) AS total_mrr
FROM ravenstack_subscriptions
GROUP BY plan_tier
ORDER BY total_mrr DESC;

-- Churn rate by plan tier
SELECT
    s.plan_tier,
    COUNT(DISTINCT a.account_id) AS total_accounts,
    COUNT(DISTINCT c.account_id) AS churned_accounts,
    ROUND(
        COUNT(DISTINCT c.account_id) * 100.0 /
        COUNT(DISTINCT a.account_id),
        2
    ) AS churn_rate
FROM ravenstack_accounts a
LEFT JOIN ravenstack_subscriptions s
    ON a.account_id = s.account_id
LEFT JOIN ravenstack_churn_events c
    ON a.account_id = c.account_id
GROUP BY s.plan_tier;

-- Churn rate by industry
SELECT
    a.industry,
    COUNT(DISTINCT a.account_id) AS total_accounts,
    COUNT(DISTINCT c.account_id) AS churned_accounts,
    ROUND(
        COUNT(DISTINCT c.account_id) * 100.0 /
        COUNT(DISTINCT a.account_id),
        2
    ) AS churn_rate
FROM ravenstack_accounts a
LEFT JOIN ravenstack_churn_events c
    ON a.account_id = c.account_id
GROUP BY a.industry;


/* SECTION 4: CHURN REASON ANALYSIS */

-- Top reasons customers churn 
SELECT
    reason_code,
    COUNT(*) AS churn_count
FROM ravenstack_churn_events
GROUP BY reason_code
ORDER BY churn_count DESC;


/* SECTION 5: SUPPORT & PRODUCT USAGE SIGNALS */

-- Overall support ticket health
SELECT
    AVG(satisfaction_score) AS avg_satisfaction,
    AVG(resolution_time_hours) AS avg_resolution_time
FROM ravenstack_support_tickets;

-- Overall feature usage health
SELECT
    AVG(usage_count) AS avg_usage,
    AVG(usage_duration_secs) AS avg_duration,
    AVG(error_count) AS avg_errors
FROM ravenstack_feature_usage;

-- Support ticket volume and satisfaction per account
SELECT
    account_id,
    COUNT(*) AS ticket_count,
    AVG(satisfaction_score) AS avg_satisfaction
FROM ravenstack_support_tickets
GROUP BY account_id
ORDER BY ticket_count DESC;

-- Feature usage and error rate per subscription
SELECT
    subscription_id,
    AVG(usage_count) AS avg_usage,
    AVG(error_count) AS avg_errors
FROM ravenstack_feature_usage
GROUP BY subscription_id
ORDER BY avg_usage;

-- Most used features across the platform
SELECT
    feature_name,
    SUM(usage_count) AS total_usage
FROM ravenstack_feature_usage
GROUP BY feature_name
ORDER BY total_usage DESC
LIMIT 10;


/* SECTION 6: CUSTOMER HEALTH SCORE MODEL
   A custom 3-signal weighted risk score combining
     - Support satisfaction  (up to 30 points)
     - Support ticket volume (up to 20 points)
     - Historical churn flag (30 points)
   Max possible score: 80
     0-34   -> Low Risk
     35-59  -> Medium Risk
     60-80  -> High Risk */

-- Reusable view: ticket count + avg satisfaction per account
CREATE VIEW support_summary AS
SELECT
    account_id,
    COUNT(*) AS ticket_count,
    AVG(satisfaction_score) AS avg_satisfaction
FROM ravenstack_support_tickets
GROUP BY account_id;

-- Core risk scoring view
CREATE VIEW customer_health_score AS
SELECT
    a.account_id,
    (
        CASE
            WHEN IFNULL(s.avg_satisfaction, 5) < 1.5 THEN 30
            WHEN IFNULL(s.avg_satisfaction, 5) < 2.5 THEN 15
            ELSE 0
        END
        +
        CASE
            WHEN IFNULL(s.ticket_count, 0) >= 8 THEN 20
            WHEN IFNULL(s.ticket_count, 0) >= 5 THEN 10
            ELSE 0
        END
        +
        CASE
            WHEN c.account_id IS NOT NULL THEN 30
            ELSE 0
        END
    ) AS risk_score
FROM ravenstack_accounts a
LEFT JOIN (
    SELECT
        account_id,
        COUNT(*) AS ticket_count,
        AVG(satisfaction_score) AS avg_satisfaction
    FROM ravenstack_support_tickets
    GROUP BY account_id
) s
    ON a.account_id = s.account_id
LEFT JOIN (
    SELECT DISTINCT account_id
    FROM ravenstack_churn_events
) c
    ON a.account_id = c.account_id;


/* SECTION 7: RISK CATEGORY BREAKDOWN  */

-- Customer count by risk category
SELECT
    CASE
        WHEN risk_score >= 60 THEN 'High Risk'
        WHEN risk_score >= 35 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_category,
    COUNT(*) AS customer_count
FROM customer_health_score
GROUP BY risk_category
ORDER BY customer_count DESC;

-- Revenue at risk by risk category
SELECT
    CASE
        WHEN h.risk_score >= 60 THEN 'High Risk'
        WHEN h.risk_score >= 35 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_category,
    COUNT(DISTINCT h.account_id) AS customers,
    ROUND(SUM(a.mrr), 2) AS revenue_at_risk
FROM customer_health_score h
JOIN ravenstack_accounts a
    ON h.account_id = a.account_id
GROUP BY risk_category;


/* SECTION 8: MASTER 360° CUSTOMER VIEW */

SELECT
    a.account_id,
    a.account_name,
    a.industry,
    a.country,
    a.plan_tier,
    a.seats,
    a.churn_flag,

    IFNULL(sub.total_mrr, 0) AS total_mrr,
    IFNULL(sub.total_arr, 0) AS total_arr,

    IFNULL(ss.ticket_count, 0) AS ticket_count,
    ROUND(IFNULL(ss.avg_satisfaction, 0), 2) AS avg_satisfaction,

    chs.risk_score,

    CASE
        WHEN chs.risk_score >= 60 THEN 'High Risk'
        WHEN chs.risk_score >= 35 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_category

FROM ravenstack_accounts a

LEFT JOIN (
    SELECT
        account_id,
        SUM(mrr_amount) AS total_mrr,
        SUM(arr_amount) AS total_arr
    FROM ravenstack_subscriptions
    GROUP BY account_id
) sub
    ON a.account_id = sub.account_id

LEFT JOIN support_summary ss
    ON a.account_id = ss.account_id

LEFT JOIN customer_health_score chs
    ON a.account_id = chs.account_id;


/* SECTION 9: WINDOW FUNCTION — REVENUE RANKING */

SELECT
    a.account_name,
    a.industry,
    sub.total_mrr,
    RANK() OVER ( 
        PARTITION BY a.industry
        ORDER BY sub.total_mrr DESC) 
        AS revenue_rank_in_industry
FROM ravenstack_accounts a
JOIN (
    SELECT
        account_id,
        SUM(mrr_amount) AS total_mrr
    FROM ravenstack_subscriptions
    GROUP BY account_id
) sub
    ON a.account_id = sub.account_id
JOIN customer_health_score chs
    ON a.account_id = chs.account_id
WHERE chs.risk_score >= 60
ORDER BY a.industry, revenue_rank_in_industry;


/* SECTION 10: DATA QUALITY CHECKS */

-- Confirm no duplicate account_ids in the health score view
SELECT
    account_id,
    COUNT(*) AS records
FROM customer_health_score
GROUP BY account_id
HAVING COUNT(*) > 1;


-- MRR distribution sanity check
SELECT
    MIN(total_mrr) AS min_mrr,
    MAX(total_mrr) AS max_mrr,
    AVG(total_mrr) AS avg_mrr
FROM (
    SELECT
        account_id,
        SUM(mrr_amount) AS total_mrr
    FROM ravenstack_subscriptions
    GROUP BY account_id
) t;
