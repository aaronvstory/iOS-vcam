# SSH to iPhone via 3uTools (Non-Interactive)

This project uses the 3uTools SSH tunnel (USB) and PuTTY tools for scripting.

## 1) Open the tunnel
1. Launch **3uTools**
2. Go to **Toolbox → Open SSH Tunnel**
3. Keep the tunnel window open (it forwards to 127.0.0.1:2222)

## 2) Required tools
Place these in the project root so the launcher can auto-detect them:
- `plink.exe`
- `pscp.exe`

## 3) Non-interactive SSH command
```
plink.exe -ssh -P 2222 -l root -pw icemat -batch 127.0.0.1 "whoami"
```

## 4) Non-interactive file copy (PC -> iPhone)
```
pscp.exe -P 2222 -pw icemat -batch ios\modified_debs\vcam_usb_forwarder.deb root@127.0.0.1:/var/root/
```

## 5) Install forwarder (non-interactive)
```
plink.exe -ssh -P 2222 -l root -pw icemat -batch 127.0.0.1 "dpkg -r vcam-usb-forwarder 2>/dev/null || true; dpkg -i /var/root/vcam_usb_forwarder.deb"
```

## 6) Start forwarder manually (if needed)
```
plink.exe -ssh -P 2222 -l root -pw icemat -batch 127.0.0.1 "/usr/local/bin/vcam_usb_forwarder >/var/log/vcam_usb_forwarder.log 2>&1 &"
```

## Notes
- If you see host key prompts, add the host key once and re-run with `-batch`.
- The launcher’s USB Forwarder Mode uses these same commands automatically.
