Varonis API Export Sample Scripts

Before running any of the sample scripts, update the config.json file with your Varonis domain and your API Key with the Enterprise Data Viewer Role.
See here for help: https://help.varonis.com/s/document-item?bundleId=ami1661784208197&topicId=kkm1726641384694.html&_LANG=enus

Audit Export
================
1. Available filters for Audit Export:
   a. startDate        Type: DateTime (mandatory) - Beginning of date range for audit events
   b. endDate          Type: DateTime (optional) - End of date range for audit events
   
2. Example of using the script: 
   .\ExportAudit.ps1 -startDate (Get-Date).AddDays(-7)
   or
   .\ExportAudit.ps1 -startDate (Get-Date).AddDays(-30) -endDate (Get-Date)
   or
   .\ExportAudit.ps1 -startDate "2025-09-01T09:00:00+00:00" -endDate "2025-09-02T21:00:00+00:00"


Events Export
================
1. Available filters for Events Export:
   a. dataSourceId     Type: Int (mandatory) - The ID of the filer you want to get event data about. Contact your Varonis SRE to get this ID.
   b. startDate        Type: DateTime (mandatory) - Beginning of date range for events
   c. endDate          Type: DateTime (optional) - End of date range for events

2. Example of using the script:
   .\ExportEvents.ps1 -dataSourceId 2 -startDate (Get-Date)
   or
   .\ExportEvents.ps1 -dataSourceId 2 -startDate (Get-Date).AddDays(-7) -endDate (Get-Date)

