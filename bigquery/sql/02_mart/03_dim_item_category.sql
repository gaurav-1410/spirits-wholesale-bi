-- Item categories. Shared by dim_item and the Excel sales budget (budget is planned per category).
CREATE OR REPLACE TABLE mart.dim_item_category AS
SELECT * FROM UNNEST([
  STRUCT('WHISKY' AS item_category_code, 'Whisky' AS item_category_name, 1 AS sort_order),
  STRUCT('GIN', 'Gin', 2),
  STRUCT('RUM', 'Rum', 3),
  STRUCT('VODKA', 'Vodka', 4),
  STRUCT('LIQUEUR', 'Liqueur', 5),
  STRUCT('BRANDY', 'Brandy & Cognac', 6),
  STRUCT('UNASSIGNED', '(Unassigned)', 99)
]);
