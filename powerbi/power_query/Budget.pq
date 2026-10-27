let
    Source        = Excel.Workbook(File.Contents(BudgetFilePath), null, true),
    BudgetSheet   = Source{[Item = "Budget", Kind = "Sheet"]}[Data],
    // the sheet has a title block above the header -> skip until the header row
    SkipTitle     = Table.Skip(BudgetSheet, each [Column1] <> "Salesperson_Code"),
    Promoted      = Table.PromoteHeaders(SkipTitle, [PromoteAllScalars = true]),
    RemoveTotal   = Table.RemoveColumns(Promoted, {"Total"}),
    OnlyDataRows  = Table.SelectRows(RemoveTotal, each [Salesperson_Code] <> null and [Salesperson_Code] <> ""),
    // months are columns (Jan..Dec) -> one row per month
    Unpivoted     = Table.UnpivotOtherColumns(
                        OnlyDataRows,
                        {"Salesperson_Code", "Salesperson", "Item_Category", "Year"},
                        "Month", "Budget_Net_Sales_EUR"),
    MonthNames    = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"},
    AddMonthNo    = Table.AddColumn(Unpivoted, "Month_No", each List.PositionOf(MonthNames, [Month]) + 1, Int64.Type),
    AddDate       = Table.AddColumn(AddMonthNo, "Budget_Month",
                        each #date(Number.From([Year]), [Month_No], 1), type date),
    Typed         = Table.TransformColumnTypes(AddDate, {
                        {"Salesperson_Code", type text},
                        {"Item_Category", type text},
                        {"Budget_Net_Sales_EUR", Currency.Type}}),
    Result        = Table.SelectColumns(Typed, {"Budget_Month", "Salesperson_Code", "Item_Category", "Budget_Net_Sales_EUR"})
in
    Result
