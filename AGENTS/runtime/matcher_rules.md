# Matcher Rules (Router)

- Query tokens are lowercased, punctuation-stripped, and normalized (`algebraically -> algebraic`, `symbolically -> symbolic`, `numerically -> numerical`).
- Stopwords are filtered from ranking/reason traces (e.g. `i`, `to`, `want`, `me`, `please`).
- Skill names are tokenized by `_`, `-`, and camelCase boundaries.
- `compute_algebraic` and `compute_numerical` receive additional domain-keyword weighting.
- Low-confidence warnings are suppressed when compute domain signals are present.
