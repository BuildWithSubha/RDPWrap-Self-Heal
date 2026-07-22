# Troubleshooting

## 3rd user still kicked (disconnect in 30 seconds)

1. Run `-Mode Repair -Force`, then restart TermService (script does this).
2. Confirm `MaxSessions=0`:

```powershell
Select-String -Path "$env:ProgramFiles\RDP Wrapper\rdpwrap.ini" -Pattern '45344fe7.*MaxSessions'
```

3. Confirm raw version section exists:

```powershell
$vi = (Get-Item $env:SystemRoot\System32\termsrv.dll).VersionInfo
'{0}.{1}.{2}.{3}' -f $vi.FileMajorPart,$vi.FileMinorPart,$vi.FileBuildPart,$vi.FilePrivatePart
```

4. Confirm wrapper loaded: `tasklist /m rdpwrap.dll`
5. Confirm with `query user` — not only RDPConf.

### Still capped at 2 on Windows Server?

Some Server builds keep enforcing Remote Admin capacity even with correct patches. Options:

- Retry after reboot
- Ensure **RDS-RD-Server is NOT installed** alongside Wrapper
- Official path: install RD Session Host + RDS CALs (different product model)

## RDPConf says not supported

```powershell
.\scripts\Install-RDPWrapSelfHeal.ps1 -Mode Repair -Force
```

If OffsetFinder fails and community ini lacks your build, wait for community offsets or generate with symbols (internet for Microsoft symbol server helps).

## "No Remote Desktop Licence Servers available"

That message is from **RDS Session Host**, not from RDP Wrapper. Either:

- Configure a license server / grace, or
- Uninstall `RDS-RD-Server` and use this Wrapper package instead (do not mix).

## Antivirus deleted rdpwrap.dll

Restore from this repo `bin\rdpwrap.dll`, add an exclusion, re-run `-Mode Install`.

## After Windows Update nothing works

Wait for reboot to finish, wait ~2 minutes for `RDPWrap-SelfHeal-Boot`, then:

```powershell
.\scripts\Install-RDPWrapSelfHeal.ps1 -Mode Status
.\scripts\Install-RDPWrapSelfHeal.ps1 -Mode Repair -Force
```
