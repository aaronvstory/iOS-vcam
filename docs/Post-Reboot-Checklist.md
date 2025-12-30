# Post-Reboot / Re-Jailbreak Checklist

**CRITICAL**: After every iPhone reboot or re-jailbreak, USB streaming will fail until these steps are completed. The jailbreak does NOT persist these settings.

## Quick Fix (Run These Commands)

From PowerShell in the project directory with iproxy already running:

```powershell
# 1. Get current SSH fingerprint (changes after sshd restart!)
$fp = (.\plink.exe -ssh -batch -P 2222 -pw icemat root@localhost exit 2>&1 | Select-String "SHA256:[A-Za-z0-9+/=]+").Matches.Value
Write-Host "Fingerprint: $fp"

# 2. Fix sshd config (idempotent - safe to run multiple times)
.\plink.exe -hostkey $fp -ssh -P 2222 -pw icemat root@localhost 'grep -q "^GatewayPorts clientspecified" /etc/ssh/sshd_config || echo "GatewayPorts clientspecified" >> /etc/ssh/sshd_config; grep -q "^AllowTcpForwarding yes" /etc/ssh/sshd_config || echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config; echo CONFIG_OK'

# 3. Restart sshd (FINGERPRINT WILL CHANGE AGAIN!)
.\plink.exe -hostkey $fp -ssh -P 2222 -pw icemat root@localhost 'launchctl unload /Library/LaunchDaemons/com.openssh.sshd.plist; launchctl load /Library/LaunchDaemons/com.openssh.sshd.plist; echo SSHD_RESTARTED'

# 4. Get NEW fingerprint after sshd restart
Start-Sleep -Seconds 2
$fp = (.\plink.exe -ssh -batch -P 2222 -pw icemat root@localhost exit 2>&1 | Select-String "SHA256:[A-Za-z0-9+/=]+").Matches.Value
Write-Host "NEW Fingerprint: $fp"

# 5. Set up loopback alias (required every boot)
.\plink.exe -hostkey $fp -ssh -P 2222 -pw icemat root@localhost 'ifconfig lo0 alias 127.10.10.10 netmask 255.255.255.255; echo ALIAS_OK'

# 6. Verify tunnel works
.\plink.exe -v -hostkey $fp -ssh -batch -T -no-antispoof -R 127.10.10.10:80:127.0.0.1:80 -R 127.10.10.10:1935:127.0.0.1:1935 -P 2222 -pw icemat root@localhost 'echo TUNNEL_TEST; sleep 3' 2>&1 | Select-String "Remote port forwarding"
# Should show "enabled" NOT "refused"
```

## What Gets Lost After Reboot

| Setting | Location | Persists? | Fix |
|---------|----------|-----------|-----|
| SSH Host Key | iPhone generates new | NO - changes on sshd restart | Use `-hostkey` fingerprint pinning |
| sshd_config changes | `/etc/ssh/sshd_config` | YES (filesystem) | Usually persists, but verify |
| GatewayPorts setting | sshd runtime | NO - needs sshd restart | Restart sshd after config change |
| Loopback alias 127.10.10.10 | Network stack | NO - lost on reboot | Run `ifconfig lo0 alias ...` |
| iproxy | PC process | NO - needs restart | Launcher handles this |

## Why Each Setting Matters

### GatewayPorts clientspecified
Without this, sshd REFUSES reverse tunnels to any address except 127.0.0.1:
```
Remote port forwarding from 127.10.10.10:80 refused
```

### AllowTcpForwarding yes
Without this, sshd won't allow ANY port forwarding.

### Loopback Alias 127.10.10.10
The iOS VCAM app is compiled to connect to `rtmp://127.10.10.10:1935`. The alias makes this address exist on the iPhone's loopback interface.

### Host Key Fingerprint
PuTTY/plink caches host keys per-host. When sshd restarts, it may regenerate keys. Using `-hostkey SHA256:...` bypasses the cache and pins to a specific fingerprint.

## Troubleshooting

### "Remote port forwarding refused"
1. Check sshd config: `sshd -T | grep gatewayports`
2. If not "clientspecified", add to config and restart sshd
3. Get NEW fingerprint after restart!

### "Host key not in manually configured list"
The fingerprint changed. Get new one:
```powershell
.\plink.exe -ssh -batch -P 2222 -pw icemat root@localhost exit 2>&1 | Select-String "SHA256:"
```

### "Connection refused" on port 2222
iproxy isn't running. Start it:
```powershell
Start-Process -WindowStyle Hidden -FilePath "C:\iProxy\iproxy.exe" -ArgumentList "2222 22"
```

### iOS app shows "Network Error"
1. Verify tunnel shows "enabled" not "refused"
2. Verify loopback alias exists: `ifconfig lo0 | grep 127.10.10.10`
3. Verify Monibuca is running on PC port 1935

## Making Settings Persist (Advanced)

To make the loopback alias persist across reboots, create a launch daemon on iPhone:

```bash
cat > /Library/LaunchDaemons/com.vcam.loopback.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vcam.loopback</string>
    <key>ProgramArguments</key>
    <array>
        <string>/sbin/ifconfig</string>
        <string>lo0</string>
        <string>alias</string>
        <string>127.10.10.10</string>
        <string>netmask</string>
        <string>255.255.255.255</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
launchctl load /Library/LaunchDaemons/com.vcam.loopback.plist
```

**Note**: This only helps with the alias. sshd config changes already persist to the filesystem.
