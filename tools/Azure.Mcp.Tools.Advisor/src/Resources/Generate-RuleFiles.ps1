# Generate JSON rule files from grouped recommendations
$grouped = Get-Content "d:\msft-advisor-mcp\tools\Azure.Mcp.Tools.Advisor\src\Resources\grouped-recommendations.json" | ConvertFrom-Json

$resourceDir = "d:\msft-advisor-mcp\tools\Azure.Mcp.Tools.Advisor\src\Resources"
$created = @()
$skipped = @()

function Convert-ARGQueryToARMQuery {
    param([string]$query, [string]$resourceType)
    
    # Remove initial resources filter completely
    $query = $query -replace "^resources\s*\|\s*", ""
    
    # Remove type filter for the specific resource type
    $query = $query -replace "where\s+type\s*[=~]+\s*[`"']$([regex]::Escape($resourceType))[`"']\s*(\||and)", ""
    $query = $query -replace "where\s+type\s+contains\s+[`"']$([regex]::Escape($resourceType))[`"']\s*(\||and)", ""
    
    # Remove leading pipes and 'where' keywords if they're now at the start
    $query = $query -replace "^\s*\|\s*", ""
    $query = $query -replace "^where\s+", ""
    
    # Remove project clauses as they're not needed for ARM template validation
    $query = $query -replace "\|\s*project\s+.*$", ""
    
    # Remove subscriptionId references
    $query = $query -replace ",\s*subscriptionId\s*$", ""
    $query = $query -replace "\|\s*project\s+subscriptionId.*$", ""
    
    # Remove id project if it's standalone
    $query = $query -replace "\|\s*project\s+id\s*$", ""
    
    # Clean up multiple pipes
    $query = $query -replace "\|\s*\|+", "|"
    
    # Trim whitespace and trailing pipes
    $query = $query.Trim()
    $query = $query.TrimEnd('|').Trim()
    $query = $query.TrimStart('|').Trim()
    
    # Remove 'and' at the beginning if present
    $query = $query -replace "^and\s+", ""
    
    # Add 'where' at the beginning if query doesn't start with it and has conditions
    if ($query -notmatch "^(where|extend|mv-expand)" -and $query.Length -gt 0) {
        $query = "where $query"
    }
    
    return $query
}

function Get-RuleId {
    param([string]$description)
    
    # Create a simple rule ID from description
    $words = $description -split '\s+' | Select-Object -First 5
    $ruleId = ($words -join '_') -replace '[^a-zA-Z0-9_]', ''
    return $ruleId
}

function Get-ResourceFileName {
    param([string]$resourceType)
    
    # Convert resource type to filename
    # e.g., microsoft.network/applicationGateways -> applicationgateway.json
    if ($resourceType -match '/') {
        $parts = $resourceType -split '/'
        $name = $parts[-1]
    } else {
        $name = $resourceType
    }
    
    # Remove microsoft prefix if present
    $name = $name -replace '^microsoft\.', ''
    
    # Convert to lowercase and remove special characters
    $name = $name.ToLower() -replace '[^a-z0-9]', ''
    
    return "$name.json"
}

# Process each resource type
foreach ($prop in $grouped.PSObject.Properties) {
    $resourceType = $prop.Name
    $recommendations = $prop.Value
    
    if ($recommendations.Count -eq 0) {
        continue
    }
    
    $fileName = Get-ResourceFileName -resourceType $resourceType
    $filePath = Join-Path $resourceDir $fileName
    
    # Skip if file already exists (except storageaccount.json which is our template)
    if ((Test-Path $filePath) -and $fileName -ne 'storageaccount.json') {
        Write-Host "Skipping $fileName - already exists" -ForegroundColor Yellow
        $skipped += [PSCustomObject]@{
            ResourceType = $resourceType
            FileName = $fileName
            Recommendations = $recommendations.Count
            Reason = "File already exists"
        }
        continue
    }
    
    $rules = @()
    
    foreach ($reco in $recommendations) {
        $description = $reco.Description
        $query = $reco.ARG_Query
        
        # Convert ARG query to ARM-compatible query
        $armQuery = Convert-ARGQueryToARMQuery -query $query -resourceType $resourceType
        
        # Skip if query is empty or too complex
        if ([string]::IsNullOrWhiteSpace($armQuery) -or $armQuery.Length -lt 5) {
            Write-Host "  Skipping rule for $resourceType - query too simple after conversion" -ForegroundColor Yellow
            $skipped += [PSCustomObject]@{
                ResourceType = $resourceType
                FileName = $fileName
                Description = $description.Substring(0, [Math]::Min(80, $description.Length))
                Reason = "Query too simple after conversion"
            }
            continue
        }
        
        # Check for joins which are complex for ARM validation
        if ($armQuery -match '\|\s*join\s+') {
            Write-Host "  Skipping complex rule for $resourceType - contains joins" -ForegroundColor Yellow
            $skipped += [PSCustomObject]@{
                ResourceType = $resourceType
                FileName = $fileName
                Description = $description.Substring(0, [Math]::Min(80, $description.Length))
                Reason = "Contains join operations"
            }
            continue
        }
        
        $ruleId = Get-RuleId -description $description
        
        # Extract fix guidance from description if possible
        $fix = if ($description -match "migrate|upgrade|update|enable|configure|use") {
            $description -replace "^.*?(migrate|upgrade|update|enable|configure|use.*?)[\.\,].*$", '$1'
        } else {
            "Review and remediate based on recommendation"
        }
        
        $rule = [PSCustomObject]@{
            ruleId = $ruleId
            description = $description
            query = $armQuery
            fix = $fix
        }
        
        $rules += $rule
    }
    
    if ($rules.Count -eq 0) {
        Write-Host "No valid rules for $resourceType" -ForegroundColor Yellow
        continue
    }
    
    # Create JSON structure
    $jsonObject = [PSCustomObject]@{
        rules = $rules
    }
    
    # Write to file with proper formatting
    $jsonContent = $jsonObject | ConvertTo-Json -Depth 10
    $jsonContent | Out-File -FilePath $filePath -Encoding UTF8
    
    Write-Host "Created $fileName with $($rules.Count) rule(s)" -ForegroundColor Green
    $created += [PSCustomObject]@{
        ResourceType = $resourceType
        FileName = $fileName
        Rules = $rules.Count
    }
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Files created: $($created.Count)"
Write-Host "Items skipped: $($skipped.Count)"

Write-Host "`n=== CREATED FILES ===" -ForegroundColor Green
$created | Format-Table -AutoSize

Write-Host "`n=== SKIPPED ITEMS ===" -ForegroundColor Yellow
$skipped | Format-Table -AutoSize

# Export summary
$summary = [PSCustomObject]@{
    Created = $created
    Skipped = $skipped
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

$summary | ConvertTo-Json -Depth 10 | Out-File "$resourceDir\generation-summary.json"
Write-Host "`nSummary exported to generation-summary.json" -ForegroundColor Cyan
