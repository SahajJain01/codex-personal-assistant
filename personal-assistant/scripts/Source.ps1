function Resolve-SourceOperation {
    param($State, $Request)
    Assert-RequiredField $Request @('operationId')
    $sourceOperation = @($State.sourceOperations | Where-Object { $_.id -eq $Request.operationId })
    if ($sourceOperation.Count -ne 1 -or $sourceOperation[0].status -ne 'pending') { throw 'No matching pending source operation.' }
    $operation = $sourceOperation[0]
    $currentHash = (Get-FileHash -LiteralPath $operation.path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($currentHash -ceq $operation.afterHash) { $operation.status = 'applied' }
    elseif ($currentHash -ceq $operation.beforeHash) { $operation.status = 'not_applied' }
    else { $operation.status = 'user_changed' }
}

function Complete-SourceCheckbox {
    param([string]$Workspace, $State, $Request)
    Assert-RequiredField $Request @('path', 'expectedHash', 'lineNumber', 'expectedLine', 'taskId', 'userReport')
    if (-not $State.config.sourceCheckboxWrites) { throw 'Source checkbox writes are disabled.' }
    $path = [IO.Path]::GetFullPath($Request.path)
    $allowed = @($State.config.todoPaths | ForEach-Object { [IO.Path]::GetFullPath($_) })
    if ($path -notin $allowed -or -not $Request.userReport) { throw 'Source must be allowlisted and completion explicitly reported.' }
    if (@($State.tasks | Where-Object { $_.id -eq $Request.taskId -and $_.status -eq 'done' }).Count -ne 1) { throw 'Commit task completion before source synchronization.' }
    $bytes = [IO.File]::ReadAllBytes($path)
    $hashAlgorithm = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($hashAlgorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hashAlgorithm.Dispose() }
    if ($hash -cne $Request.expectedHash) { throw 'Source changed. Reread and remap the checkbox.' }
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { $offset = 3 }
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    $lines = [regex]::Split($text, '(?<=\n)')
    $lineIndex = [int]$Request.lineNumber - 1
    if ($lineIndex -lt 0 -or $lineIndex -ge $lines.Length -or
        $lines[$lineIndex].TrimEnd("`r", "`n") -cne $Request.expectedLine -or
        $Request.expectedLine -notmatch '^\s*[-*+] \[ \] ') { throw 'Source line is not the exact unchecked task.' }
    $lines[$lineIndex] = [regex]::Replace($lines[$lineIndex], '^(\s*[-*+] \[) (\])', '${1}x${2}')
    $replacement = $lines -join ''
    if ($offset -eq 3) { $replacement = [string][char]0xFEFF + $replacement }
    $operation = [pscustomobject]@{ id = [guid]::NewGuid().ToString('N'); path = $path; taskId = $Request.taskId
        beforeHash = $hash; afterHash = Get-TextHash $replacement; status = 'pending'; userReport = $Request.userReport
    }
    $State.sourceOperations = @($State.sourceOperations) + @($operation)
    Save-AssistantState $Workspace $State 'Prepared source checkbox completion'
    # Journal first, then hold an exclusive source handle and change only the checkbox byte.
    $backup = Join-Path (Join-Path $Workspace 'journal') "$($operation.id).source-backup"
    [IO.File]::WriteAllBytes($backup, $bytes)
    $sourceStream = [IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $currentHash = ([BitConverter]::ToString($algorithm.ComputeHash($sourceStream))).Replace('-', '').ToLowerInvariant()
        if ($currentHash -cne $hash) { throw 'Source changed before write; completion remains pending.' }
        $afterBytes = [Text.Encoding]::UTF8.GetBytes($replacement)
        if ($afterBytes.Length -ne $bytes.Length) { throw 'Checkbox patch unexpectedly changed source length.' }
        $changedOffset = -1
        for ($index = 0; $index -lt $bytes.Length; $index++) {
            if ($bytes[$index] -ne $afterBytes[$index]) {
                if ($changedOffset -ge 0) { throw 'Checkbox patch must change exactly one byte.' }
                $changedOffset = $index
            }
        }
        if ($changedOffset -lt 0) { throw 'Checkbox patch did not change the source.' }
        [void]$sourceStream.Seek($changedOffset, [IO.SeekOrigin]::Begin)
        $sourceStream.WriteByte($afterBytes[$changedOffset])
        $sourceStream.Flush($true)
    }
    finally { $sourceStream.Dispose(); $algorithm.Dispose() }
    $operation.status = 'applied'
}
