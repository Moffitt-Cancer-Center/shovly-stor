# Varonis’ sample code(s) are provided on an “as is” and “as available” basis and without any warranty of any kind.  
# Any use of Varonis’ sample code(s) is optional at client’s sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis’ sample code(s), their specific functions or their availability, reliability, or ability to meet client’s needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis’ sample code(s) from time to time, without notice and for any reason.

function ValidateAccessPath {
	Param 
	(
		$path
	)
    $path = "$($path.TrimEnd('\'))"
    $filename = get-date -Format yyyy-MM-dd_HH-mm-ss
    $filename +="$filename.txt"
	Write-Host "Confirming $path"
	$exists = Test-Path $path 
	if ($exists -eq $true) 
	{
		Write-Host "Path exists, moving on"
        try 
        {
            Write-Host "Confirming ability to create a file in this path, $path\$filename"
            $null = New-Item -path $path -name "$filename" -Force
        }
        catch 
        {
            Write-Host "can't write to path - likely access denied $path" -foregroundcolor red
            return $false
        }
        
        
        $test = Test-Path "$path\$filename"
        if ($test -eq $true)
        {
            Write-Host "Able to write, removing temp file $path\$filename"
            Remove-Item $path\$filename
            return $true
        }
        else 
        {
            Write-Host "can't write to path $path" -foregroundcolor red
            return $false
        }
	}
	else 
	{
		write-Host "Path not found, please confirm $path is valid" -foregroundcolor red
		return $false
	}

}