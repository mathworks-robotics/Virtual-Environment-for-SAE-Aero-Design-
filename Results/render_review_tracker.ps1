param(
    [string]$StatePath = "Results\\review_tracker_state.json",
    [string]$OutputPath = "Results\\SAE_Aero_Review_Tracker.rtf"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Escape-Rtf {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    $escaped = $Text.Replace("\", "\\")
    $escaped = $escaped.Replace("{", "\{")
    $escaped = $escaped.Replace("}", "\}")
    $escaped = $escaped -replace "(`r`n|`n|`r)", "\par "
    return $escaped
}

function Add-Line {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$Text
    )

    [void]$Builder.Append((Escape-Rtf $Text))
    [void]$Builder.Append("\par ")
}

function Add-Bold-Line {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$Text
    )

    [void]$Builder.Append("\b ")
    [void]$Builder.Append((Escape-Rtf $Text))
    [void]$Builder.Append("\b0\par ")
}

function Add-Blank {
    param([System.Text.StringBuilder]$Builder)
    [void]$Builder.Append("\par ")
}

$state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
$issues = @($state.issues)

$statusOrder = @(
    "Awaiting approval",
    "Approved - fix not started",
    "In progress",
    "Pending - not approved",
    "Fixed",
    "Closed without fix"
)

$priorityOrder = @{
    "P0" = 0
    "P1" = 1
    "P2" = 2
    "P3" = 3
}

$orderedIssues = $issues | Sort-Object `
    @{ Expression = { $priorityOrder[$_.priority] } }, `
    @{ Expression = { $_.id } }

$builder = New-Object System.Text.StringBuilder
[void]$builder.Append("{\rtf1\ansi\deff0")
[void]$builder.Append("{\fonttbl{\f0 Calibri;}}")
[void]$builder.Append("\viewkind4\uc1\pard\fs22 ")

Add-Bold-Line -Builder $builder -Text $state.title
Add-Line -Builder $builder -Text ("Project: {0}" -f $state.project)
Add-Line -Builder $builder -Text ("Created: {0}" -f $state.created)
Add-Line -Builder $builder -Text ("Last updated: {0}" -f $state.lastUpdated)
Add-Blank -Builder $builder

Add-Bold-Line -Builder $builder -Text "Workflow"
for ($i = 0; $i -lt $state.workflow.Count; $i++) {
    Add-Line -Builder $builder -Text ("{0}. {1}" -f ($i + 1), $state.workflow[$i])
}
Add-Blank -Builder $builder

Add-Bold-Line -Builder $builder -Text "Issue Summary"
foreach ($issue in $orderedIssues) {
    Add-Line -Builder $builder -Text ("[{0}] {1} | {2} | {3} | {4}" -f $issue.id, $issue.priority, $issue.severity, $issue.status, $issue.title)
}
Add-Blank -Builder $builder

Add-Bold-Line -Builder $builder -Text "Status Groups"
foreach ($status in $statusOrder) {
    $group = @($orderedIssues | Where-Object { $_.status -eq $status })
    if ($group.Count -gt 0) {
        Add-Bold-Line -Builder $builder -Text $status
        foreach ($issue in $group) {
            Add-Line -Builder $builder -Text ("[{0}] {1}" -f $issue.id, $issue.title)
        }
        Add-Blank -Builder $builder
    }
}

Add-Bold-Line -Builder $builder -Text "Detailed Issues"
foreach ($issue in $orderedIssues) {
    Add-Bold-Line -Builder $builder -Text ("[{0}] {1}" -f $issue.id, $issue.title)
    Add-Line -Builder $builder -Text ("Priority: {0} | Severity: {1} | Status: {2}" -f $issue.priority, $issue.severity, $issue.status)
    Add-Line -Builder $builder -Text ("Scope: {0}" -f $issue.scope)
    Add-Line -Builder $builder -Text ("Evidence: {0}" -f $issue.evidence)
    Add-Line -Builder $builder -Text ("Proposed fix: {0}" -f $issue.proposedFix)
    Add-Line -Builder $builder -Text ("Relevant files: {0}" -f (@($issue.files) -join ", "))
    Add-Line -Builder $builder -Text ("Approval: {0}" -f $issue.approval)
    if (-not [string]::IsNullOrWhiteSpace($issue.resolution)) {
        Add-Line -Builder $builder -Text ("Resolution: {0}" -f $issue.resolution)
    }
    if (@($issue.log).Count -gt 0) {
        Add-Line -Builder $builder -Text "Log:"
        foreach ($entry in @($issue.log)) {
            Add-Line -Builder $builder -Text ("  - {0}" -f $entry)
        }
    }
    Add-Blank -Builder $builder
}

[void]$builder.Append("}")
Set-Content -Path $OutputPath -Value $builder.ToString() -Encoding ASCII
Write-Output ("Tracker rendered to {0}" -f $OutputPath)
