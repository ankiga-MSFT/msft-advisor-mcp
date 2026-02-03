# Process Advisor Recommendations CSV and generate JSON rule files
$csv = Import-Csv "d:\Ad-Hoc Files\Advisor_Recos.csv"

# Tables to exclude (non-resources tables)
$excludeTables = @('dnsresources', 'appserviceresources', 'insightsresources', 'maintenanceresources')

# Group by resource type
$grouped = @{}
$excluded = @()

foreach ($row in $csv) {
    $query = $row.ARG_Query
    $description = $row.Description
    
    # Check if query uses excluded tables
    $usesExcludedTable = $false
    foreach ($table in $excludeTables) {
        if ($query -match "\b$table\b") {
            $usesExcludedTable = $true
            $excluded += [PSCustomObject]@{
                Description = $description
                Reason = "Uses $table table"
            }
            break
        }
    }
    
    if ($usesExcludedTable) {
        continue
    }
    
    # Extract primary resource type from query
    if ($query -match "type\s*[=~]+\s*[`"']([^`"']+)[`"']") {
        $resourceType = $matches[1]
        if (-not $grouped.ContainsKey($resourceType)) {
            $grouped[$resourceType] = @()
        }
        $grouped[$resourceType] += $row
    }
    elseif ($query -match 'type\s+contains\s+[`"'']([^`"'']+)[`"'']') {
        $resourceType = $matches[1]
        if (-not $grouped.ContainsKey($resourceType)) {
            $grouped[$resourceType] = @()
        }
        $grouped[$resourceType] += $row
    }
    elseif ($query -match "where\s+[`"']?type[`"']?\s*==\s*[`"']([^`"']+)[`"']") {
        $resourceType = $matches[1]
        if (-not $grouped.ContainsKey($resourceType)) {
            $grouped[$resourceType] = @()
        }
        $grouped[$resourceType] += $row
    }
}

Write-Host "`n=== ANALYSIS RESULTS ===" -ForegroundColor Cyan
Write-Host "Total recommendations in CSV: $($csv.Count)"
Write-Host "Excluded recommendations: $($excluded.Count)"
Write-Host "Unique resource types identified: $($grouped.Keys.Count)"
Write-Host "`n=== RESOURCE TYPES ===" -ForegroundColor Cyan
$grouped.Keys | Sort-Object | ForEach-Object { 
    Write-Host "$_ : $($grouped[$_].Count) recommendation(s)"
}

Write-Host "`n=== EXCLUDED RECOMMENDATIONS ===" -ForegroundColor Yellow
$excluded | Format-Table -AutoSize

# Export for reference
$grouped | ConvertTo-Json -Depth 10 | Out-File "d:\msft-advisor-mcp\tools\Azure.Mcp.Tools.Advisor\src\Resources\grouped-recommendations.json"
$excluded | ConvertTo-Json -Depth 10 | Out-File "d:\msft-advisor-mcp\tools\Azure.Mcp.Tools.Advisor\src\Resources\excluded-recommendations.json"

Write-Host "`nExported grouped recommendations to grouped-recommendations.json" -ForegroundColor Green
Write-Host "Exported excluded recommendations to excluded-recommendations.json" -ForegroundColor Green
