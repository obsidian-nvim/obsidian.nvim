---
id: note_with_MathJax
---

# Inline and Display Modes

By the law of large numbers we have that $\widehat{\mathbb{V}[\theta_{i}]} \to \mathbb{V}[\theta_{i}]$, hence
$$
\begin{flalign*}
  \hat{\beta}_{1} &\approx \beta_{1} + \frac{\frac{1}{n} \sum_{i=1}^{n} \left( X_{i} - \mu_{X} \right) U_{i}}{\frac{1}{n} \sum_{i=1}^{n} \left( X_{i} - \mu_{X} \right)^{2}} &&\\
  \mathbb{V} \left[ \hat{\beta}_{1} \right] &= \mathbb{V} \left[ \beta_{1} + \frac{\frac{1}{n} \sum_{i=1}^{n} \left( X_{i} - \mu_{X} \right) U_{i}}{\sigma_{X}^{2}} \right] &&\\
  &= \mathbb{V} \left[ \beta_{1} \right] + \mathbb{V} \left[ \frac{\frac{1}{n} \sum_{i=1}^{n} \left( X_{i} - \mu_{X} \right) U_{i}}{\sigma_{X}^{2}} \right] &&\\
  &= \left( \frac{1}{\sigma_{X}^{2}} \right)^{2} \cdot \left( \frac{1}{n} \right)^{2} \cdot \underbrace{\mathbb{V} \left[ \sum_{i=1}^{n} \left( X_{i} - \mu_{X} \right) U_{i} \right]}_{\textcolor{yellow}{*_{1}}} &&\\
  &= \left( \frac{1}{\sigma_{X}^{2}} \right)^{2} \cdot \left( \frac{1}{n} \right)^{2} \cdot n \mathbb{V} \left[ \left( X_{i} - \mu_{X} \right) U_{i} \right] &&\\
  &= \frac{1}{n} \cdot \frac{\mathbb{V} \left[ \left( X_{i} - \mu_{X} \right) U_{i} \right]}{\left( \sigma_{X}^{2} \right)^{2}} &&\\
\end{flalign*}
$$

Therefore, $\hat{\beta}_{1} \overset{\text{CLT}}{\sim} \mathcal{N} \left( \beta_{1}, \sigma_{\hat{\beta}_{1}}^{2} \right)$, where $\sigma_{\hat{\beta}_{1}}^{2} = \frac{\mathbb{V} \left[ \left( X_{i} - \mu_{X} \right) U_{i} \right]}{n \cdot \left( \sigma_{X}^{2} \right)^{2}}$.
