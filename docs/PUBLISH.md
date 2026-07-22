# Publishing & discoverability checklist

Maintainer guide for shipping updates to [BuildWithSubha/RDPWrap-Self-Heal](https://github.com/BuildWithSubha/RDPWrap-Self-Heal) and maximizing GitHub / Google visibility.

---

## 1. Before you push

- [ ] README credits upstream projects
- [ ] `LICENSE` + `NOTICE` present
- [ ] No machine-specific diagnostics / passwords in the tree
- [ ] Decide whether to keep `tools/OffsetFinder/**/sym/**` PDBs (large; Microsoft symbol terms) — remove if unsure
- [ ] Test on a clean VM: `Install.bat` → `query user` with 3 sessions
- [ ] README headings and FAQ still match common search phrases (Windows Update, not supported, MaxSessions, concurrent RDP)

## 2. Push from this folder

```powershell
cd "D:\Work\RDPWrap Self-Heal"

git add .
git status
git commit -m "Describe the change clearly"
git push -u origin main
```

## 3. Optional: exclude PDBs to shrink the repo

```powershell
Remove-Item -Recurse -Force .\tools\OffsetFinder\64bit\sym
```

OffsetFinder can still download symbols when the machine has internet.

---

## 4. GitHub About (SEO / discoverability)

### Recommended description (≤350 characters)

```text
Self-healing RDP Wrapper for Windows 10/11/Server — auto-repairs multi-session Remote Desktop after Windows Update by regenerating termsrv.dll offsets and fixing MaxSessions.
```

Shorter alternative:

```text
Fix RDP Wrapper after Windows Update. Regenerates termsrv offsets, enables concurrent multi-session RDP on Server, and auto-repairs on boot.
```

### Recommended topics (GitHub → About → Topics)

Add these topics so the repo appears in GitHub topic search and related-repo sidebars:

```text
rdp
rdpwrap
rdp-wrapper
remote-desktop
windows
windows-10
windows-11
windows-server
windows-update
powershell
termsrv
multi-session
self-heal
homelab
sysadmin
```

### How to set them in the UI

1. Open https://github.com/BuildWithSubha/RDPWrap-Self-Heal  
2. Click the gear icon next to **About**  
3. Paste the description  
4. Add the topics above  
5. Save  

### How to set them with GitHub CLI (if installed)

```powershell
gh repo edit BuildWithSubha/RDPWrap-Self-Heal `
  --description "Self-healing RDP Wrapper for Windows 10/11/Server — auto-repairs multi-session Remote Desktop after Windows Update by regenerating termsrv.dll offsets and fixing MaxSessions." `
  --add-topic rdp `
  --add-topic rdpwrap `
  --add-topic rdp-wrapper `
  --add-topic remote-desktop `
  --add-topic windows `
  --add-topic windows-10 `
  --add-topic windows-11 `
  --add-topic windows-server `
  --add-topic windows-update `
  --add-topic powershell `
  --add-topic termsrv `
  --add-topic multi-session `
  --add-topic self-heal `
  --add-topic homelab `
  --add-topic sysadmin
```

---

## 5. Releases (helps GitHub + Google)

Create a tagged release with a ZIP users can download without cloning:

```powershell
git tag -a v1.0.0 -m "v1.0.0: initial self-heal release"
git push origin v1.0.0

# With GitHub CLI:
gh release create v1.0.0 --title "v1.0.0 — RDPWrap Self-Heal" --notes "First public release: install, repair, status, uninstall + boot/daily self-heal."
```

Release notes should mention: Windows 10/11/Server, Windows Update repair, concurrent RDP, MaxSessions, OffsetFinder.

---

## 6. Content SEO reminders (README)

Keep these natural in the README (already targeted):

| Intent | Phrases to keep visible |
|--------|-------------------------|
| Broken after update | RDP Wrapper after Windows Update, `termsrv.dll`, `rdpwrap.ini` |
| Status confusion | `[not supported]`, `[fully supported]`, third user disconnect |
| Server cap | Windows Server, MaxSessions=0, 2 RDP sessions |
| Goal | multi-session RDP, concurrent Remote Desktop, Windows 10/11 |
| Proof | `query user`, Active sessions |

Avoid keyword stuffing. Prefer clear problem → solution → verification copy.
