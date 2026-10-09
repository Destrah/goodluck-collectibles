# Pack resale analysis

Source: checked-in `fivem/data/catalog.json`, `sets.json`, and current `config.lua`. Live MySQL definitions may differ; the in-game Pack pricing tab uses the live server definitions. Observed graded population is zero for this offline snapshot.

Factory simulations use up to 5,000 packs per set. Clean averages are exact weighted expectations. All figures are dollars, before pack purchase cost and grading fees. Suggested grading assumes all defects are found; actual grader adjustments can differ.

## Base Set — Trading card buyer

| Scenario | Average / pack | Median | 10th–90th percentile | Average / 12-pack box |
|---|---:|---:|---:|---:|
| Clean raw (exact average) | $24.25 | $16.00 | $11.00–$36.00 | $290.97 |
| Factory raw (simulation) | $23.26 | $15.00 | $10.00–$35.00 | $279.08 |
| Factory suggested grades (simulation) | $36.05 | $24.00 | $15.00–$58.00 | $432.64 |

For factory raw cards, at a $250 pack price:
- Customer average net return: $-226.74.
- Sampled chance of recovering $250: 0.42%.
- 95% confidence interval for the simulated mean: $22.07–$24.45.
- Business buyback margin = sale price after fees − supply cost − average card buyback. Enter real supply costs and fees in the UI before choosing a retail price.

| Proposed pack price | Customer average net (fresh raw) | Sampled recovery chance | Business margin after buyback, before supply cost/fees |
|---|---:|---:|---:|
| $10 | $13.26 | 97.58% | $-13.26 |
| $15 | $8.26 | 53.88% | $-8.26 |
| $20 | $3.26 | 31.34% | $-3.26 |
| $25 | $-1.74 | 19.24% | $1.74 |
| $30 | $-6.74 | 13.14% | $6.74 |
| $35 | $-11.74 | 10.34% | $11.74 |
| $40 | $-16.74 | 8.86% | $16.74 |
| $50 | $-26.74 | 7.04% | $26.74 |
| $100 | $-76.74 | 2.60% | $76.74 |
| $250 | $-226.74 | 0.42% | $226.74 |

For example, with $5 supply cost, no fees, and a 20% revenue margin including all fresh-card buyback, the target pack price is `ceil((5 + expected resale) / 0.8)`: **$36**. This is a worked example, not a configured supply cost. Buyer funding and actual demand still matter.

| Clean slot contribution | Cards | Expected resale |
|---|---:|---:|
| Common slots | 3 | $5.91 |
| Uncommon-or-higher slot | 1 | $3.16 |
| Rare-or-higher slot | 1 | $15.18 |

| All five cards hypothetically at grade | Expected pack resale |
|---|---:|
| 1 | $6.95 |
| 5 | $16.67 |
| 8 | $28.98 |
| 9 | $41.83 |
| 9.5 | $49.63 |
| 10 | $71.31 |

These fixed-grade rows are scenarios, not expected grade frequencies. The factory-grade simulation uses the grading model’s actual suggested-grade distribution.

| Card / print | Tier | Expected copies / pack | Clean offer | Contribution / pack |
|---|---|---:|---:|---:|
| Nate Gatto / Character Outline | rare | 0.328947 | $5.00 | $1.64 |
| County Heat Gauntlet / Gold Chase | legendary | 0.028571 | $50.00 | $1.43 |
| County Heat Gauntlet / Rare | rare | 0.184211 | $5.00 | $0.92 |
| Sunset Run / Standard | uncommon | 0.290909 | $3.00 | $0.87 |
| Nate Gatto / Reverse Holo | common | 0.288462 | $3.00 | $0.87 |
| Nate Gatto / Character + Car Outline | ultra_rare | 0.054645 | $15.00 | $0.82 |
| Nate Gatto / Rainbow Chase | common | 0.115385 | $7.00 | $0.81 |
| BCSO Moto / Standard | uncommon | 0.398778 | $2.00 | $0.80 |
| Peggy Moto / Prism | common | 0.096923 | $8.00 | $0.78 |
| County Heat Gauntlet / Prism Full Art | ultra_rare | 0.030601 | $25.00 | $0.77 |
| Dark Sky / Full Art | ultra_rare | 0.038251 | $20.00 | $0.77 |
| Pier Park Man / Legendary Etched | legendary | 0.006122 | $123.00 | $0.75 |
| Air Juanito / Ultra Rare | ultra_rare | 0.018361 | $41.00 | $0.75 |
| Pier Park Man / Legendary Rainbow | legendary | 0.011224 | $67.00 | $0.75 |
| Pier Park Man / Legendary Aurora | legendary | 0.003061 | $245.00 | $0.75 |
| Nate Gatto / Base | common | 0.750000 | $1.00 | $0.75 |
| Holo Mask Lab / Reference Base | rare | 0.006579 | $114.00 | $0.75 |
| Sunset Run / Aurora | uncommon | 0.124675 | $6.00 | $0.75 |
| Air Juanito / Oil Slick | ultra_rare | 0.007869 | $95.00 | $0.75 |
| Dark Sky / Rare | rare | 0.148994 | $5.00 | $0.74 |
| BCSO Moto / Reverse | uncommon | 0.185638 | $4.00 | $0.74 |
| BCSO Moto / Full Art Prism | ultra_rare | 0.049180 | $15.00 | $0.74 |
| Dark Sky / Illustration Rare | rare | 0.081269 | $9.00 | $0.73 |
| Peggy Moto / Etched | common | 0.174462 | $4.00 | $0.70 |
| Peggy Moto / Base | common | 0.697846 | $1.00 | $0.70 |
| Business Fudge / Base | common | 0.657692 | $1.00 | $0.66 |
| Business Fudge / Reverse Holo | common | 0.219231 | $3.00 | $0.66 |
| Holo Mask Lab / Electric Outline Demo | ultra_rare | 0.000273 | $1000.00 | $0.27 |
| Holo Mask Lab / Dedicated Outline Mask | ultra_rare | 0.000273 | $1000.00 | $0.27 |
| Holo Mask Lab / Subject Prism Mask | ultra_rare | 0.000273 | $1000.00 | $0.27 |
| Holo Mask Lab / Water Subject Demo | ultra_rare | 0.000273 | $1000.00 | $0.27 |
| Holo Mask Lab / Triple Mask Chase | legendary | 0.000146 | $1000.00 | $0.15 |
| Holo Mask Lab / Flame Hybrid Demo | legendary | 0.000146 | $1000.00 | $0.15 |
| Holo Mask Lab / Flame Smooth Demo | legendary | 0.000146 | $1000.00 | $0.15 |
| Holo Mask Lab / Flame Hybrid 50% Demo | legendary | 0.000146 | $1000.00 | $0.15 |
| Holo Mask Lab / Flame Anime Demo | legendary | 0.000146 | $1000.00 | $0.15 |
| Holo Mask Lab / Flame Smoky Demo | legendary | 0.000146 | $1000.00 | $0.15 |
| Holo Mask Lab / Flame Accent Demo | legendary | 0.000146 | $1000.00 | $0.15 |
