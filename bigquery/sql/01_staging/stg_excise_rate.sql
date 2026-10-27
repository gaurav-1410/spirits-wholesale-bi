-- German spirits excise duty (Alkoholsteuer), converted to EUR per litre of pure alcohol
CREATE OR REPLACE VIEW staging.stg_excise_rate AS
SELECT
  Product_Group                                AS product_group,
  Valid_From                                   AS valid_from,
  COALESCE(Valid_To, DATE '9999-12-31')        AS valid_to,
  Rate_EUR_per_hl_pure_alcohol / 100           AS rate_eur_per_l_pure_alcohol,
  Legal_Basis                                  AS legal_basis
FROM raw.excise_duty_rates;
