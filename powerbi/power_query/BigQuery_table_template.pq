let
    Source  = GoogleBigQuery.Database([BillingProject = GcpProjectId, UseStorageApi = false]),
    Project = Source{[Name = GcpProjectId]}[Data],
    Dataset = Project{[Name = "mart", Kind = "Schema"]}[Data],
    Table   = Dataset{[Name = "fact_sales", Kind = "Table"]}[Data]
in
    Table
