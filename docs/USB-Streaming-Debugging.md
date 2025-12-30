# USB Streaming Debugging Guide

**Last Updated**: 2025-12-30

This document captures everything learned while debugging USB streaming issues. Use this to avoid repeating the same debugging circles.

---

## Table of Contents

1. [Quick Diagnostic Commands](#quick-diagnostic-commands)
2. [Common Error Messages & Solutions](#common-error-messages--solutions)
3. [The Post-Reboot Problem](#the-post-reboot-problem)
4. [SSH Host Key Issues](#ssh-host-key-issues)
5. [IPv6 False Positives](#ipv6-false-positives)
6. [sshd Configuration](#sshd-configuration)
7. [Tunnel Verification](#tunnel-verification)
8. [iOS App "Network Error"](#ios-app-network-error)
9. [Process Management](#process-management)
10. [Debugging Flowchart](#debugging-flowchart)

---

## Quick Diagnostic Commands

Run these from the project directory to diagnose issues:

### 1. Check All Services Running
```powershell
Get-Process -Name plink,python,monibuca,iproxy -ErrorAction SilentlyContinue |
  Select-Object Name,Id | Format-Table
```

**Expected**: All 4 processes should be running.

### 2. Check Ports Are Bound
```powershell
Get-NetTCPConnection -LocalPort 80,1935,2222 -ErrorAction SilentlyContinue |
  Select-Object LocalPort,State,OwningProcess
```

**Expected**: Ports 80, 1935, 2222 all in LISTEN state.

### 3. Get Current SSH Fingerprint
```powershell
.\plink.exe -4 -ssh -batch -P 2222 -pw icemat root@127.0.0.1 exit 2>&1 |
  Select-String "SHA256:"
```

### 4. Check iPhone sshd Config
```powershell
$fp = "<fingerprint from above>"
.\plink.exe -4 -hostkey $fp -ssh -P 2222 -pw icemat root@127.0.0.1 'sshd -T | grep -E "gatewayports|allowtcpforwarding"'
```

**Expected**: `gatewayports clientspecified` and `allowtcpforwarding yes`

### 5. Check iPhone Loopback Alias
```powershell
.\plink.exe -4 -hostkey $fp -ssh -P 2222 -pw icemat root@127.0.0.1 'ifconfig lo0 | grep inet'
```

**Expected**: Should show both `127.0.0.1` AND `127.10.10.10`

### 6. Check iPhone Listening Ports
```powershell
.\plink.exe -4 -hostkey $fp -ssh -P 2222 -pw icemat root@127.0.0.1 'netstat -an | grep "127.10.10.10.*LISTEN"'
```

**Expected**: Two lines showing 127.10.10.10:80 and 127.10.10.10:1935 LISTEN

### 7. Test Tunnel Acceptance (Verbose)
```powershell
.\plink.exe -4 -v -hostkey $fp -ssh -batch -T -no-antispoof `
  -R 127.10.10.10:80:127.0.0.1:80 `
  -R 127.10.10.10:1935:127.0.0.1:1935 `
  -P 2222 -pw icemat root@127.0.0.1 'echo TEST; sleep 3' 2>&1 |
  Select-String "Remote port forwarding"
```

**Expected**: `Remote port forwarding from 127.10.10.10:80 enabled` (NOT "refused")

---

## Common Error Messages & Solutions

### "Host key not in manually configured list"

**Cause**: SSH host key changed (sshd restarted, phone rebooted)

**Solution**: Re-probe the fingerprint:
```powershell
$fp = (.\plink.exe -4 -ssh -batch -P 2222 -pw icemat root@127.0.0.1 exit 2>&1 |
  Select-String "SHA256:").Matches.Value
Write-Host "New fingerprint: $fp"
```

Then use `-hostkey $fp` in all subsequent commands.

---

### "Remote port forwarding from 127.10.10.10:* refused"

**Cause**: sshd doesn't have `GatewayPorts clientspecified` configured

**Solution**:
```powershell
# Fix sshd config
.\plink.exe -4 -hostkey $fp -ssh -P 2222 -pw icemat root@127.0.0.1 @'
grep -q "^GatewayPorts clientspecified" /etc/ssh/sshd_config || echo "GatewayPorts clientspecified" >> /etc/ssh/sshd_config
grep -q "^AllowTcpForwarding yes" /etc/ssh/sshd_config || echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config
launchctl unload /Library/LaunchDaemons/com.openssh.sshd.plist
launchctl load /Library/LaunchDaemons/com.openssh.sshd.plist
echo FIXED
'@

# CRITICAL: Get NEW fingerprint after sshd restart!
Start-Sleep 2
$fp = (.\plink.exe -4 -ssh -batch -P 2222 -pw icemat root@127.0.0.1 exit 2>&1 |
  Select-String "SHA256:").Matches.Value
Write-Host "New fingerprint after restart: $fp"
```

---

### "Failed to connect to ::1: Connection refused"

**Cause**: plink trying IPv6 first before falling back to IPv4

**NOT AN ERROR** - This is informational. The connection will succeed via IPv4.

**Prevention**: Always use `-4` flag to force IPv4:
```powershell
.\plink.exe -4 -ssh ...  # Forces IPv4 only
```

---

### "Access denied" or "password" errors

**Cause**: Wrong SSH password

**Solution**: Check the password in Configuration Settings (Option C in launcher), or use default `alpine`

---

### iOS App Shows "Network Error"

**Possible Causes** (check in order):

1. **plink not running** - Check `Get-Process plink`
2. **Tunnel ports not bound on iPhone** - Run diagnostic #6 above
3. **Loopback alias missing** - Run diagnostic #5 above
4. **Wrong .deb installed** - Must use `127.10.10.10` IP version

**Quick Fix**:
```powershell
# Restart everything
.\plink.exe -4 -hostkey $fp -ssh -P 2222 -pw icemat root@127.0.0.1 'ifconfig lo0 alias 127.10.10.10 netmask 255.255.255.255'

Start-Process -WindowStyle Hidden -FilePath ".\plink.exe" -ArgumentList @(
  '-4','-hostkey',$fp,'-ssh','-batch','-T','-no-antispoof',
  '-R','127.10.10.10:80:127.0.0.1:80',
  '-R','127.10.10.10:1935:127.0.0.1:1935',
  '-P','2222','-pw','icemat','root@127.0.0.1','cat'
)
```

---

## The Post-Reboot Problem

**After iPhone reboot or re-jailbreak, USB streaming WILL fail** because:

| What Gets Lost | Why It Matters |
|----------------|----------------|
| sshd config changes | GatewayPorts reverts to default "no" |
| SSH host keys | May regenerate, breaking `-hostkey` pinning |
| Loopback alias | 127.10.10.10 doesn't exist on fresh boot |
| iproxy connection | USB forwarding needs restart |

**The launcher now handles all of this automatically**, but if it fails:

1. Run Option [K] to kill all processes
2. Run Option [U] again - it will auto-fix sshd config
3. If still failing, see [sshd Configuration](#sshd-configuration)

---

## SSH Host Key Issues

### Why Host Keys Change

- **sshd restart** - May regenerate keys
- **iPhone reboot** - Fresh sshd instance
- **Re-jailbreak** - SSH package reinstalled

### How The Launcher Handles It

1. **Probes fingerprint** before any SSH operation
2. **Uses `-hostkey` pinning** to bypass cache
3. **Retries once** if host key mismatch detected
4. **Re-probes after sshd restart** (config fix changes keys!)

### Manual Key Management

```powershell
# Clear PuTTY's cached keys for this host
$path = 'HKCU:\Software\SimonTatham\PuTTY\SshHostKeys'
Remove-ItemProperty -Path $path -Name "ssh-ed25519@2222:127.0.0.1" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $path -Name "ssh-ed25519@2222:localhost" -ErrorAction SilentlyContinue

# Get fresh fingerprint
.\plink.exe -4 -ssh -batch -P 2222 -pw icemat root@127.0.0.1 exit 2>&1
```

---

## IPv6 False Positives

### The Bug We Fixed

Old code:
```powershell
if ($verifyOut -match 'refused|prohibited') {
    # FALSE POSITIVE! Matches "Failed to connect to ::1: Connection refused"
}
```

New code:
```powershell
if ($verifyOut -match 'Remote port forwarding from .* (refused|prohibited)') {
    # Only matches actual tunnel refusal
}
```

### Why IPv6 Appears

plink tries IPv6 (`::1`) before IPv4 (`127.0.0.1`) when connecting to `localhost`. The connection to `::1` fails (no IPv6 listener), then succeeds on IPv4.

### Prevention

Always use:
- `-4` flag to force IPv4
- `root@127.0.0.1` instead of `root@localhost`

---

## sshd Configuration

### Required Settings

Add to `/etc/ssh/sshd_config` on iPhone:
```
AllowTcpForwarding yes
GatewayPorts clientspecified
```

### Why These Matter

| Setting | Without It |
|---------|-----------|
| `AllowTcpForwarding yes` | No port forwarding at all |
| `GatewayPorts clientspecified` | Can only bind to 127.0.0.1, not 127.10.10.10 |

### Verify Settings Are Active

```powershell
.\plink.exe -4 -hostkey $fp -ssh -P 2222 -pw icemat root@127.0.0.1 'sshd -T | grep -E "^gatewayports|^allowtcpforwarding"'
```

**Must show**:
```
gatewayports clientspecified
allowtcpforwarding yes
```

### If Settings Don't Appear

sshd may not have reloaded. Force restart:
```powershell
.\plink.exe -4 -hostkey $fp -ssh -P 2222 -pw icemat root@127.0.0.1 @'
launchctl unload /Library/LaunchDaemons/com.openssh.sshd.plist
launchctl load /Library/LaunchDaemons/com.openssh.sshd.plist
echo RESTARTED
'@
```

**Then get NEW fingerprint** - it changes after restart!

---

## Tunnel Verification

### What "enabled" vs "refused" Means

| Verbose Output | Meaning |
|---------------|---------|
| `Remote port forwarding from 127.10.10.10:1935 enabled` | sshd accepted the tunnel - will work |
| `Remote port forwarding from 127.10.10.10:1935 refused` | sshd rejected - check GatewayPorts config |
| `Failed to connect to ::1: Connection refused` | Harmless IPv6 fallback - ignore this |

### The Launcher's Verification Flow

1. **Probe with `-v` flag** to get verbose output
2. **Parse for "enabled"** = success
3. **Parse for "Remote port forwarding from .* refused"** = sshd config issue
4. **Only start real tunnel if verification passes**

---

## iOS App "Network Error"

### Debugging Checklist

1. **Is plink running?**
   ```powershell
   Get-Process plink
   ```

2. **Are ports listening on iPhone?**
   ```powershell
   .\plink.exe ... 'netstat -an | grep "127.10.10.10.*LISTEN"'
   ```
   Should show BOTH :80 and :1935

3. **Is the alias set up?**
   ```powershell
   .\plink.exe ... 'ifconfig lo0 | grep 127.10.10.10'
   ```

4. **Is the right .deb installed?**
   - Must be `127.10.10.10` version, not WiFi IP version
   - Check with: Settings > iOS-VCAM on the phone

5. **Is Monibuca receiving the stream?**
   - Open http://localhost:8081/ in browser
   - Should show active stream if OBS is publishing

### Quick Recovery

```powershell
# Kill everything
Stop-Process -Name plink,python,monibuca,iproxy -Force -ErrorAction SilentlyContinue

# Run launcher Option [U] again
```

---

## Process Management

### What Each Process Does

| Process | Port | Purpose |
|---------|------|---------|
| `iproxy` | 2222→22 | USB to SSH forwarding |
| `python` | 80 | Flask auth server |
| `monibuca` | 1935 | RTMP streaming server |
| `plink` | N/A | SSH tunnel to iPhone |

### Safe Process Killing

**NEVER DO THIS** (kills Claude Code!):
```powershell
Stop-Process -Name node  # BAD!
taskkill /F /IM node.exe  # BAD!
```

**DO THIS INSTEAD**:
```powershell
# Kill by specific PID
Stop-Process -Id 12345 -Force

# Or kill only our processes
Stop-Process -Name plink,iproxy -Force -ErrorAction SilentlyContinue
```

### Checking Port Usage

```powershell
# Who's using port 1935?
Get-NetTCPConnection -LocalPort 1935 |
  Select-Object OwningProcess |
  ForEach-Object { Get-Process -Id $_.OwningProcess }
```

---

## Debugging Flowchart

```
iOS App Shows "Network Error"
            │
            ▼
    Is plink running?
    ┌───────┴───────┐
   NO              YES
    │               │
    ▼               ▼
  Start          Check iPhone ports
  tunnel         (netstat on iPhone)
    │           ┌───────┴───────┐
    │          NO              YES
    │           │               │
    │           ▼               ▼
    │     Check sshd        Check alias
    │     config            (ifconfig lo0)
    │           │          ┌───────┴───────┐
    │           │         NO              YES
    │           │          │               │
    │           │          ▼               ▼
    │           │     Add alias       Check .deb
    │           │          │          version
    │           │          │               │
    │           ▼          ▼               ▼
    │     Fix sshd    Restart       Reinstall
    │     config      tunnel        correct .deb
    │           │          │               │
    └───────────┴──────────┴───────────────┘
                       │
                       ▼
              Re-probe fingerprint
              (may have changed!)
                       │
                       ▼
                 Try again
```

---

## Lessons Learned (The Hard Way)

### 1. Always Force IPv4
```powershell
.\plink.exe -4 ...  # ALWAYS use -4
```
IPv6 `::1` connection failures pollute logs and cause false positives.

### 2. Fingerprint Changes After sshd Restart
After ANY sshd restart, you MUST re-probe the fingerprint. The launcher handles this, but manual debugging must too.

### 3. "refused" Isn't Always Refused
The word "refused" appears in IPv6 fallback messages. Only `Remote port forwarding from .* refused` means actual tunnel refusal.

### 4. sshd -T Shows Effective Config
Don't just `cat sshd_config` - use `sshd -T` to see what sshd is actually using:
```bash
sshd -T | grep gatewayports
```

### 5. Don't Use ssh.exe For Automation
OpenSSH's `ssh` prompts for passwords interactively. Use `plink.exe -pw` for automation.

### 6. The Launcher Now Handles Post-Reboot
Option [U] automatically:
- Probes fingerprint
- Checks/fixes sshd config
- Sets up loopback alias
- Verifies tunnel acceptance BEFORE starting
- Starts the actual tunnel only if everything passes

---

## Related Documentation

- [Post-Reboot-Checklist.md](Post-Reboot-Checklist.md) - Quick recovery steps
- [Streaming-Guide.md](Streaming-Guide.md) - General streaming setup
- [CLAUDE.md](../CLAUDE.md) - Developer notes

---

## Version History

| Date | Changes |
|------|---------|
| 2025-12-30 | Initial version after debugging session |
| | Added IPv6 false positive fix |
| | Added auto sshd config fix |
| | Added fingerprint re-probe after sshd restart |
