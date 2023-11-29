param (
    [Parameter(Mandatory)]
    $customer_id, 
    [Parameter(Mandatory)]
    $ingest_token
)

$config_urls = @(  
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/fluent-bit/windows/fluent-bit.conf",
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/fluent-bit/windows/observe_logs.conf",
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/fluent-bit/windows/observe_metrics.conf",
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/fluent-bit/windows/observe_custom.conf"
)

$url = "https://packages.fluentbit.io/windows/fluent-bit-2.2.0-win64.msi"

# Sanitize host name
if ($observe_host_name -eq 'collect.observeinc.com') {
    $observe_host_name = "${customer_id}.${observe_host_name}"
}

$observe_host_name = $observe_host_name -replace "https://", "" -replace ".com/", ".com" -replace "http://", ""
$temp_dir = "C:\temp\observe"
$msiexec_args = "/I ${temp_dir}\fluent-bit-2.2.0-win64.msi /qn"

Invoke-WebRequest -Uri $url -OutFile "$temp_dir\fluent-bit-2.2.0-win64.msi"
Start-Process "msiexec.exe" -ArgumentList $msiexec_args -Wait -ErrorAction Stop

$configFolder = "C:\Program Files\fluent-bit\conf"
foreach ($url in $config_urls) {
    # Extract the filename from the URL
    $filename = [System.IO.Path]::GetFileName($url)

    # Construct the destination path
    $destinationPath = Join-Path -Path $configFolder -ChildPath $filename

    # Download the file and save it to the destination path
    Invoke-WebRequest -Uri $url -OutFile $destinationPath

    Write-Host "Downloaded and saved: $filename to $destinationPath"
}

Restart-Service fluent-bit
