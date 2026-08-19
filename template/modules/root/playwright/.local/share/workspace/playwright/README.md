# Playwright feature

The image contains Python, browser operating-system libraries, and helper
scripts. It deliberately does not install a global Playwright package or a
browser revision. Each project owns matching versions.

Example Python project:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install playwright
playwright install chromium
workspace-desktop start
playwright-browser --url http://127.0.0.1:3000
```
