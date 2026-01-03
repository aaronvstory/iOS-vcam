# Test if SSH tunnel is working by checking what's listening on iPhone
$plinkPath = ".\plink.exe"
$sshPassword = "i55555"  # From your saved password

Write-Host "Testing SSH connection and tunnel setup..."

# Check what's listening on iPhone loopback
$result = & $plinkPath -ssh -batch -pw $sshPassword root@localhost -P 2222 'netstat -an | grep -E "127\.(0\.0\.1|10\.10\.10).*LISTEN"; ifconfig lo0 | grep inet'
Write-Host "iPhone status:"
Write-Host $result
