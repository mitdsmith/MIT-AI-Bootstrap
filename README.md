# MIT-AI Bootstrap

Public bootstrap launcher for the private MonrealIT MIT-AI installer repo.

Windows one-liner:

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/mitdsmith/MIT-AI-Bootstrap/main/bootstrap-private-repo-windows.ps1 -UseBasicParsing | iex"
```

What it does:
- installs Git with winget if needed
- configures Git credential storage if needed
- prompts for GitHub username + PAT token when cloning the private repo
- clones or updates `https://github.com/Monreal-IT/MIT-AI.git`
- runs `install-monrealit-ai-wsl.ps1` from that private checkout

The main MIT-AI repo stays private; only this launcher is public.
