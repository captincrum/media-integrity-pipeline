# -------------------------[ Unified Error Catalog ]------------------------- #

$Global:UM_ErrorCatalog = @{

    LibraryRootNotFound = @{
        Code     = 1001
        Severity = "Error"
        Message  = 'ERROR: The path for "Library Root" was not found.'
    }

    RepairedPathNotFound = @{
        Code     = 1002
        Severity = "Error"
        Message  = 'The path for "Repaired Output" was not found.'
    }

    PipelineInitFailure = @{
        Code     = 2001
        Severity = "Error"
        Message  = 'Pipeline job did not initialize correctly.'
    }

    InvalidMode = @{
        Code     = 2002
        Severity = "Error"
        Message  = 'Invalid pipeline mode specified.'
    }
}

function UM-ThrowError {
    param(
        [Parameter(Mandatory)]
        [string]$Code
    )

    if (-not $Global:UM_ErrorCatalog.ContainsKey($Code)) {
        return [pscustomobject]@{
            Type    = "Console"
            Message = "Unknown error code: $Code"
        }
    }

    $err = $Global:UM_ErrorCatalog[$Code]

    return [pscustomobject]@{
        Type     = "Console"
        Code     = $err.Code
        Severity = $err.Severity
        Message  = $err.Message
        Human    = $err.Human
    }
}
