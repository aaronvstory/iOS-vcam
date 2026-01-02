# iPhone SSH Quick Reference

Quick guide for establishing SSH connection to jailbroken iPhones via USB.

## Prerequisites

- `C:\iProxy\iproxy.exe` and `C:\iProxy\idevice_id.exe` (libimobiledevice)
- iPhone connected via USB cable
- OpenSSH installed on jailbroken iPhone

## Device UDIDs

| Device | UDID |
|--------|------|
| iPhone SE2 | `00008030-001229C01146402E` |
| iPhone 8 | `308e6361884208deb815e12efc230a028ddc4b1a` |

## Step 1: Start iproxy (USB → SSH forwarding)

```powershell
# For iPhone 8:
C:\iProxy\iproxy.exe -u 308e6361884208deb815e12efc230a028ddc4b1a 2222 22

# For iPhone SE2:
C:\iProxy\iproxy.exe -u 00008030-001229C01146402E 2222 22
```

Keep this running in a separate terminal.

## Step 2: SSH in

```powershell
# Using plink (PuTTY):
plink.exe -ssh -P 2222 -pw icemat root@127.0.0.1

# Or standard ssh:
ssh -p 2222 root@127.0.0.1
# Password: icemat
```

## One-Liner (run command and exit)

```powershell
plink.exe -ssh -batch -P 2222 -pw icemat root@127.0.0.1 "uname -a"
```

## Credentials

| Field | Value |
|-------|-------|
| User | `root` |
| Password | `icemat` |
| Port | `2222` (localhost, forwarded by iproxy) |

## Troubleshooting

### List connected devices
```powershell
C:\iProxy\idevice_id.exe -l
```

### If connection refused
1. Ensure iproxy is running with correct UDID
2. Check iPhone is unlocked and trusted
3. Verify OpenSSH is installed on iPhone

### If host key error
```powershell
# Get current fingerprint
plink.exe -ssh -batch -P 2222 -pw icemat root@127.0.0.1 exit 2>&1 | Select-String "SHA256:"

# Use with -hostkey flag
plink.exe -hostkey "SHA256:xxxxx" -ssh -P 2222 -pw icemat root@127.0.0.1
```
