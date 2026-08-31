# Gross Margin Decomposition: A Hybrid SQL & SHAP Driver Analysis
##  Executive Summary
Revenue increased from $16.52M in 2024 to $19.00M in 2025, yet gross margin declined from 36% to 32%, while gross profit increased only modestly from $6.00M to $6.11M.

This project investigates why stronger revenue performance failed to translate into proportional gross-profit growth.

The analysis combines:
- SQL-based Price-Volume-Mix-Cost(PVMC) decomposition to quantify the financial drivers of year-over-year gross profit movement.
- Product-level decomposition to identify the SKUs and categories responsible for deterioration or improvement.
XGBoost with SHAP analysis to test whether changes in unit cost, pricing and discounting exhibit meaninful nonlinear relationships with transaction-level margin deterioration.

The analysis finds that volume growth was the principal positive contributor to gross profit, but much of its benefit was absorbed by rising costs and adverse product mix. At product level, the largest deteriorations were concentrated in Electronics, while several small Appliance SKUs benefited from favorable mix and demand growth.

The nonlinear analysis found predominantly monotonic, near-linear relationships rather than robust operating thresholds.

Consequently, the recommendations focus on targeted cost recovery, profitable product mix and SKU-specific margin controls rather than arbitrary universal discount limits.

## Business Problem
The business generated substantial revenue growth between 2024 and 2025, but the quality of that growth deteriorated

| Metric | 2024 | 2025 |
|---|---:|---:|
| Revenue | $16.52M | $19.00M |
| Gross Profit | $6.00M | $6.11M |
| Gross Margin | 36% | 32% |

The central business question is:

>**What is driving deterioration in gross margin performance despite revenue growth, where is the pressure concentrated, and are there nonlinear operating thresholds that management should consider?**

This was investigated thrpugh three progressively deeper analytical layers:

1. What changed financially?

Decompose gross-profit movement into price, volume, mix and cost effects.

2. Where did it change?

Identify the products and categories responsible for the strongest positive and negative contributions.

3. How do the underlying operating changes relate to margin deterioration?

Test whether cost, pricing and discount movements exhibit meaningful nonlinear behaviour or threshold effects.

## Analytical Approach
### 1. Financial Baseline

Annual financial performance was first compared to establish the scale of the problem.

```sql
SELECT
    EXTRACT(YEAR FROM transaction_date::DATE) AS year,
    ROUND(SUM(net_revenue)) AS total_revenue,
    ROUND(SUM(net_revenue - cogs)) AS gross_profit,
    ROUND(100 * (SUM(net_revenue - cogs) / SUM(net_revenue))) AS gross_margin
FROM
    sales_ledger
GROUP BY
    1
ORDER BY
    year;
```

Although revenue increased substantially in 2025, gross profit increased by only approximately $102K, while gross margin fell by 4 percentage points.

This established the need to determine which economic forces were absorbing the benefit of revenue growth.

### 2. Price–Volume–Mix–Cost Decomposition

A PVMC bridge was aggregated to the business level.

```sql
SELECT
    SUM(r.q_25 * (r.p_25 - r.p_24)) AS price_effect,
    SUM((r.q_24 * (t.vol_factor - 1)) * r.m_24) AS volume_effect,
    SUM((r.q_25 - (r.q_24 * t.vol_factor)) * r.m_24) AS mix_effect,
    SUM(r.q_25 * (r.c_24 - r.c_25)) AS cost_effect
FROM sku_rates r
CROSS JOIN totals t;
```

The decomposition attributed the movement in gross profit to four components:

| Driver | Gross Profit Impact |
|---|---:|
| Volume | +$936.6K |
| Realized Price | +$135.1K |
| Mix | -$110.8K |
| Cost | -$859.1K |

### Key finding
The business generated substantial incremental profit through higher sales volume, but approximately $859K of gross-profit pressure from higher unit costs absorbed most of that benefit.

Product mix created a further $111K drag, while changes in realized selling price provided only a relatively modest offset.

Therefore, the central problem was not insufficient demand.

It was the economics of the incremental volume being generated.

### 3. Product-Level Contribution Analysis

The business-level decomposition was extended to individual products to determine where the aggregate effects originated.

```sql
SELECT
    r.product_id,
    r.product_category,
    r.product_subcategory,
    r.q_24 AS units_2024,
    r.q_25 AS units_2025,
    ROUND(r.gp_24, 2) AS gp_2024,
    
    -- PVMC Drivers per Product
    ROUND((r.q_24 * (t.vol_factor - 1)) * r.unit_gross_profit_24, 2) AS volume_effect,
    ROUND((r.q_25 - (r.q_24 * t.vol_factor)) * r.unit_gross_profit_24, 2) AS mix_effect,
    ROUND(r.q_25 * (r.p_25 - r.p_24), 2) AS price_effect,
    ROUND(r.q_25 * (r.c_24 - r.c_25), 2) AS cost_effect,
    
    ROUND(r.gp_25, 2) AS gp_2025,
    ROUND(r.gp_25 - r.gp_24, 2) AS gross_profit_change
FROM sku_rates r
CROSS JOIN totals t
ORDER BY gross_profit_change ASC;
```

**Electronics: concentration of gross-profit deterioration:**

Several of the largest gross-profit declines were concentrated in Electronics:

- P011 – Home Tech: approximately −$18.7K
- P004 – Accessories: approximately −$18.4K
- P001 – Accessories: approximately −$15.5K
- P009 – Home Tech: approximately −$15.3K
- P006 – Audio: approximately −$12.4K

Across these products, adverse cost effects outweighed positive contributions from volume and realized price.

**Small Appliances: favourable mix and growth:**

Conversely, several Small Appliance SKUs generated strong gross-profit improvement:

- P021: approximately +$39.0K
- P023: approximately +$34.9K
- P022: approximately +$24.3K

Their favourable mix effects contributed approximately +$41.9K, +$38.5K and +$31.9K, respectively, helping them absorb higher costs while still expanding gross profit.

**P027: volume growth without economic improvement:**


P027 illustrates why volume alone is an insufficient performance objective.

The product generated approximately:

- +$94.1K volume effect

but simultaneously experienced:

- −$63.4K mix effect
- −$52.2K cost effect

leaving 2025 gross profit approximately $9.1K below 2024.

This demonstrates the distinction between volume growth and profitable volume growth.

### 4. Nonlinear Margin Analysis

The PVMC decomposition established the financial drivers of gross-profit movement.

A separate machine-learning layer was then used to answer a narrower question:

>**Do changes in the key operating variables exhibit meaningful nonlinear relationships with margin deterioration?**


```sql
SELECT
    tm.*,
    b.base_unit_price,
    b.base_unit_cost,
    b.base_discount_rate,
    b.base_margin_pct,

    -- Unit-cost movement from product baseline
    100 * (
        tm.unit_cost
        / NULLIF(b.base_unit_cost, 0)
        - 1
    ) AS unit_cost_change_pct,

    -- List-price movement from product baseline
    100 * (
        tm.unit_price
        / NULLIF(b.base_unit_price, 0)
        - 1
    ) AS list_price_change_pct,

    -- Discount movement in percentage points
    100 * (
        tm.discount_rate
        - b.base_discount_rate
    ) AS discount_change_pp,

    -- ML target
    tm.gross_margin_pct
        - b.base_margin_pct
        AS margin_delta_pp

FROM transaction_metrics AS tm

INNER JOIN baseline_2024 AS b
    ON tm.product_id = b.product_id

WHERE tm.year = 2025
```

For each 2025 transaction, operating movements were calculated relative to the corresponding product's 2024 baseline:

-unit-cost change %
-list-price change %
-discount change in percentage points
-transaction margin change in percentage points

The objective of this layer was not to rediscover the accounting determinants of gross margin. Price, discount and cost are mechanically related to margin.

Instead, the model was used to examine the shape of those relationships and determine whether nonlinear behaviour or operating thresholds were present.

### 5. Model Development

Three regression approaches were compared:

- Linear Regression
- Random Forest
- XGBoost


**Train/Test Split:**
```python
train_orders, test_orders = train_test_split(
    ml_data['order_id'].unique(),
    test_size=0.20,
    random_state=42
)

train_mask = ml_data['order_id'].isin(train_orders)
test_mask = ml_data['order_id'].isin(test_orders)

x_train = x.loc[train_mask]
x_test = x.loc[test_mask]

y_train = y.loc[train_mask]
y_test = y.loc[test_mask]
```

The train/test split was performed at order level, preventing transaction lines belonging to the same order from being distributed between the training and test sets.

**Modeling Pipeline:**
```python
preprocessor = ColumnTransformer(
    transformers=[
        (
            'cat', 
            OneHotEncoder(handle_unknown='ignore',
                          sparse_output=False
            ), 
            cat_features
        ),
        ('num', 'passthrough', num_features)
    ]
)

xgb_pipeline = Pipeline(steps=[
    ('preprocessor', preprocessor),
    ('model', XGBRegressor(random_state=42))
])
```

Initial test performance was:

| Model | R² | RMSE |
|---|---:|---:|
| Linear Regression | 0.9885 | 0.3026 |
| Random Forest | 0.9961 | 0.1759 |
| XGBoost | 0.9960 | 0.1789 |


**Cross-Validation and Hyperparameter Tuning:**
```python
xgb_search = RandomizedSearchCV(
    estimator=xgb_pipeline,
    param_distributions=xgb_param_grid,
    n_iter=30,
    cv=5,
    scoring='neg_root_mean_squared_error',
    random_state=42,
    n_jobs=-1
)

xgb_search.fit(x_train, y_train)
```

Five-fold cross-validation subsequently produced the lowest average RMSE for XGBoost, after which the model was tuned using randomized hyperparameter search.

The tuned model achieved:

**Test R²: 0.9986**
**Test RMSE: 0.1048 percentage points**

Because the target is mathematically related to several model inputs, these performance metrics are not interpreted as evidence of novel predictive discovery. Model interpretation is instead used to evaluate relationship shape.


### 6. SHAP Relationship Analysis
SHAP analysis showed that the strongest modeled relationships with margin change were concentrated in:

- Unit-cost change
- Discount change
- List-price change

while product subcategory and store effects were substantially smaller.

**SHAP Explainability:**
```python
best_xgb = xgb_search.best_estimator_

preprocessor = best_xgb.named_steps['preprocessor']
xgb_model = best_xgb.named_steps['model']

x_test_transformed = preprocessor.transform(x_test)

explainer = shap.TreeExplainer(xgb_model)
shap_values = explainer(x_test_transformed)

shap.summary_plot(
    shap_values.values, 
    x_test_transformed, 
    feature_names=feature_names
)
```
![SHAP Summary Plot](assets\SHAP_Summary_Plot.png)

SHAP dependence analysis was then used to examine whether these relationships contained meaningful nonlinear thresholds.
```python
shap.dependence_plot(
    'unit_cost_change_pct', 
    shap_values.values, 
    x_test_transformed, 
    feature_names=feature_names
)

shap.dependence_plot(
    'discount_change_pp', 
    shap_values.values, 
    x_test_transformed, 
    feature_names=feature_names
)

shap.dependence_plot(
    'list_price_change_pct', 
    shap_values.values, 
    x_test_transformed, 
    feature_names=feature_names
)
```

**Result:**

The relationships were predominantly monotonic and near-linear.

- Increasing unit costs were associated with progressively greater margin deterioration.
- Discount expansion was associated with progressively greater deterioration.
- Increasing list prices were associated with improved margin outcomes.
- Discount expansion showed some deviation at the extreme end, but not enough to establish a robust operating threshold.

The evidence therefore did not support claiming a universal nonlinear threshold.

## Recommendation

1. Target cost recovery in underperforming Electronics SKUs

Cost pressure is concentrated rather than uniform.

Prioritize supplier renegotiation, alternative sourcing and selective cost pass-through for the Electronics SKUs generating the largest cost drag rather than applying indiscriminate business-wide cost reductions.

2. Protect and selectively scale Small Appliances

P021, P023 and P022 demonstrate favourable demand and mix dynamics despite cost pressure.

Maintain inventory availability and commercial support for these products and favour them when allocating incremental sales effort.

3. Prioritize profitable volume, particularly for P027

Further volume growth should not be pursued independently of unit economics.

For products such as P027, management should first improve cost recovery and/or redirect incremental demand toward more profitable products within the category.

4. Introduce SKU-level margin floors for discount decisions

The analysis does not support a universal discount threshold.

Discount governance should therefore be based on the economics of each SKU: proposed discounts should preserve a minimum expected gross margin after considering the product's current unit cost.


## Strategic Takeaway

The business does not primarily have a growth problem. It has a growth-quality problem.

Higher volume generated approximately $937K in incremental gross profit, but cost pressure and adverse mix absorbed most of that benefit.

The commercial priority should therefore shift from maximizing sales volume to maximizing profitable volume growth; recovering costs where deterioration is concentrated, protecting favourable product mix, and governing discounts according to SKU-level margin economics.

## Tools & Technologies

- **SQL (DuckDB):** Data transformation, financial metric construction, annual performance analysis, PVMC decomposition, and SKU-level contribution analysis
- **Python:** Data preparation, statistical analysis, machine learning, and visualization
- **Pandas & NumPy:** Data manipulation and feature preparation
- **Scikit-learn:** Preprocessing, model pipelines, train/test splitting, cross-validation, and hyperparameter tuning
- **XGBoost:** Nonlinear regression modelling
- **SHAP:** Model interpretation and nonlinear relationship analysis
- **Power BI:** Executive KPI reporting and PVMC visualization
