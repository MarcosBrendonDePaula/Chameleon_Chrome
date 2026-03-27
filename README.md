# Chameleon Browser

Chromium fork with native C++ anti-fingerprinting protections. Each browser profile produces a unique, deterministic fingerprint that resists cross-profile tracking.

## Quick Start

```bash
# Build (incremental)
build_chameleon.bat

# Launch with interactive profile manager
run_chameleon.bat

# Direct CLI launch
out\Default\chrome.exe --user-data-dir="E:\chameleon_profiles\myprofile" --chameleon-seed=<hex128> --chameleon-locale=en-US,en
```

## Command Line Flags

### Core Flags

| Flag | Description | Example |
|------|-------------|---------|
| `--chameleon-seed=<hex>` | 128-bit hex seed for deterministic fingerprint. Same seed = same fingerprint across sessions. | `--chameleon-seed=a1b2c3d4e5f6...` |
| `--chameleon-locale=<langs>` | Override `navigator.language/languages`. | `--chameleon-locale=en-US,en` |
| `--chameleon-modules=<list>` | Enable only specific modules (comma-separated). Omit to enable all. | `--chameleon-modules=canvas,webgl,audio` |
| `--chameleon-brand=<brand>` | Spoof browser branding. Format: `BrandName,MajorVersion,FullVersion`. | `--chameleon-brand=Google Chrome,120,120.0.6099.130` |
| `--chameleon-pierce` | Enable `__chameleon` API in isolated worlds for bot automation. | `--chameleon-pierce` |

### Math Noise (V8 layer)

Math noise runs inside V8 and uses separate flags via `--js-flags`:

```bash
--js-flags="--chameleon-math-noise --chameleon-math-seed=0x<hex>"
```

## Modules

| Module | ID | Flag Name | What it does |
|--------|----|-----------|--------------|
| Canvas | canvas | Pixel noise on getImageData/toDataURL/toBlob, measureText width noise |
| WebGL | webgl | readPixels noise, invisible tag on RENDERER/VENDOR strings |
| WebGL Params | webglparams | Spoofs MAX_TEXTURE_SIZE etc, shuffles getSupportedExtensions |
| Audio | audio | Noise on getChannelData + OfflineAudioContext.startRendering |
| WebRTC | webrtc | Filters host/srflx/prflx ICE candidates |
| Device Memory | memory | Seed-derived value from {2, 4, 8, 16} |
| Client Rects | rects | Sub-pixel noise on getBoundingClientRect/getClientRects |
| Screen | screen | colorDepth=32, pixelDepth=32, seed-derived taskbar offset |
| Locale | locale | Overrides navigator.language/languages |
| Fonts | fonts | Blocks ~30% non-safe fonts, adds measureText width noise |
| Navigator | navigator | Spoofs hardwareConcurrency, platform, maxTouchPoints |
| Math | math | Multiplicative noise on Math.sin/cos/tan/atan2/log/exp/sinh/cosh/tanh |

### Module Control

```bash
# All modules (default)
--chameleon-seed=abc123

# Specific modules only
--chameleon-modules=canvas,webgl,audio,navigator,fonts

# Disable all modules (baseline test)
--chameleon-modules=none
```

## Bot Automation (`__chameleon` API)

When `--chameleon-pierce` is active, Chameleon injects a `__chameleon` object into every **isolated world** (CDP/DevTools contexts). This API provides trusted C++ actions that are undetectable by page JavaScript.

### Available Functions

| Function | Description |
|----------|-------------|
| `__chameleon.click(element)` | Trusted click (`isTrusted: true`, `kFromUserAgent`). Indistinguishable from a real user click. |
| `__chameleon.query(selector)` | Deep CSS query that searches through closed shadow roots. Returns the first matching Element or null. |

### How it Works

```
Bot (Python)
  |
  |-- WebSocket --> Chrome DevTools Protocol
  |                   |
  |                   |-- Target.getTargets
  |                   |     (finds cross-origin iframes like Turnstile)
  |                   |
  |                   |-- Target.attachToTarget
  |                   |     (connects to iframe's renderer process)
  |                   |
  |                   |-- Page.createIsolatedWorld
  |                   |     (creates privileged JS context inside iframe)
  |                   |
  |                   |-- Runtime.evaluate
  |                         (runs JS with __chameleon available)
  |                         |
  |                         |-- __chameleon.query(selector)
  |                         |     C++ DeepQuery: searches all elements
  |                         |     including closed shadow roots
  |                         |
  |                         |-- __chameleon.click(element)
  |                               C++ DispatchSimulatedClick
  |                               with kFromUserAgent
  |                               -> isTrusted: true
```

**Why it's undetectable:**
- `__chameleon` only exists in isolated worlds, never in the page's main world
- Shadow DOM piercing only works in isolated worlds
- Clicks are dispatched as `kFromUserAgent` (not `kFromDebugger`), generating `isTrusted: true`
- No `--disable-site-isolation` needed — works cross-process via CDP Target sessions
- Page JavaScript sees a completely normal browser

### Complete Example: Solving Cloudflare Turnstile

```python
"""Solve Cloudflare Turnstile using Chameleon Browser."""
import json
import time
import random
import urllib.request
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
import websocket


# --- CDP Helper ---
def cdp_send(ws, method, params=None, session_id=None, timeout=10):
    """Send a CDP command via WebSocket and wait for response."""
    msg_id = random.randint(1, 999999)
    msg = {'id': msg_id, 'method': method, 'params': params or {}}
    if session_id:
        msg['sessionId'] = session_id
    ws.send(json.dumps(msg))
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            ws.settimeout(1)
            data = json.loads(ws.recv())
            if data.get('id') == msg_id:
                return data.get('result', {}), data.get('error')
        except websocket.WebSocketTimeoutException:
            continue
    return None, {'message': 'timeout'}


# --- 1. Start Chameleon Browser ---
seed = ''.join(random.choices('0123456789abcdef', k=32))

options = Options()
options.binary_location = "E:\\CHAMALEON\\out\\Default\\chrome.exe"
options.add_argument(f"--user-data-dir=E:\\chameleon_profiles\\bot_{seed[:8]}")
options.add_argument(f"--chameleon-seed={seed}")
options.add_argument("--chameleon-locale=en-US,en")
options.add_argument("--chameleon-pierce")          # enables __chameleon API
options.add_argument("--remote-allow-origins=*")    # allows WebSocket CDP

service = Service("E:\\CHAMALEON\\out\\Default\\chromedriver.exe")
driver = webdriver.Chrome(service=service, options=options)

# --- 2. Get WebSocket URL ---
port = driver.capabilities['goog:chromeOptions']['debuggerAddress'].split(':')[-1]
resp = urllib.request.urlopen(f'http://127.0.0.1:{port}/json')
pages = json.loads(resp.read())
ws_url = next(p['webSocketDebuggerUrl'] for p in pages if p['type'] == 'page')

# --- 3. Navigate and fill form ---
driver.get("https://example.com/page-with-turnstile")
time.sleep(5)
driver.execute_script("""
    document.querySelector('input[name="email"]').value = 'user@example.com';
""")

# --- 4. Connect to DevTools via WebSocket ---
ws = websocket.create_connection(ws_url)

# --- 5. Find the Turnstile iframe target ---
result, _ = cdp_send(ws, 'Target.getTargets')
turnstile_target = None
for t in result['targetInfos']:
    if 'challenges.cloudflare.com' in t.get('url', ''):
        turnstile_target = t
        break

if not turnstile_target:
    print("Turnstile not found on page")
    ws.close()
    driver.quit()
    exit(1)

# --- 6. Attach to the Turnstile iframe process ---
result, _ = cdp_send(ws, 'Target.attachToTarget', {
    'targetId': turnstile_target['targetId'],
    'flatten': True
})
session_id = result['sessionId']

# --- 7. Get frame tree and create isolated world ---
cdp_send(ws, 'Page.enable', session_id=session_id)
cdp_send(ws, 'Runtime.enable', session_id=session_id)
time.sleep(1)

result, _ = cdp_send(ws, 'Page.getFrameTree', session_id=session_id)
frame_id = result['frameTree']['frame']['id']

result, _ = cdp_send(ws, 'Page.createIsolatedWorld', {
    'frameId': frame_id,
    'worldName': 'chameleon_bot'
}, session_id=session_id)
ctx_id = result['executionContextId']

# --- 8. Use __chameleon to find and click the checkbox ---
result, _ = cdp_send(ws, 'Runtime.evaluate', {
    'expression': """
        (function() {
            // __chameleon.query searches through closed shadow roots
            var checkbox = __chameleon.query("input[type='checkbox']");
            if (!checkbox) return 'not found';

            // __chameleon.click dispatches a trusted C++ click (isTrusted: true)
            __chameleon.click(checkbox);
            return 'clicked';
        })()
    """,
    'contextId': ctx_id,
    'returnByValue': True
}, session_id=session_id)

print(f"Click result: {result['result']['value']}")
ws.close()

# --- 9. Wait for token ---
token = None
for i in range(15):
    time.sleep(1)
    token = driver.execute_script("""
        var t = document.querySelector("input[name='cf-turnstile-response']");
        return t && t.value ? t.value : '';
    """)
    if token and len(token) > 10:
        print(f"Token: {token[:60]}...")
        break

# --- 10. Submit form with token ---
if token:
    driver.execute_script("document.querySelector('form').submit()")
    print("Form submitted!")
else:
    print("No token received")

driver.quit()
```

### Running Multiple Bots in Parallel

Each bot instance is fully independent with its own seed/fingerprint:

```bash
# Run 2 bots
python tests/e2e/multi_bot.py -n 2

# Run 5 bots with custom wallet
python tests/e2e/multi_bot.py -n 5 -w 0xYourWallet...
```

Each bot:
- Separate Chrome process with unique seed/fingerprint
- Independent WebSocket CDP connection
- Own profile directory (cookies, storage)
- Limit is your machine's RAM (~300-400MB per instance)

## Anti-Detection

### WebDriver Detection
- `navigator.webdriver` returns `false`
- All automation indicators hidden at C++ level

### Fingerprint Uniqueness
- Same seed always produces same fingerprint (deterministic)
- Different seeds produce different fingerprints
- Canvas, WebGL, Audio, Math, Fonts all produce unique noise per seed

### `__chameleon` API Security
- Only exists in CDP isolated worlds, never in page's main world
- Page JavaScript cannot detect its presence
- `__chameleon.click()` generates `isTrusted: true` events (kFromUserAgent)
- No site isolation disabled — works cross-process via CDP Target sessions
- Fingerprinting services see normal browser behavior

### Test Sites
- [fingerprint.com](https://fingerprint.com) — primary target (suspect score)
- [browserleaks.com/canvas](https://browserleaks.com/canvas) — canvas fingerprint
- [browserleaks.com/webgl](https://browserleaks.com/webgl) — WebGL fingerprint
- [audiofingerprint.openwpm.com](https://audiofingerprint.openwpm.com) — audio fingerprint

## E2E Tests

```bash
# Pierce test (isolated world vs main world, 10 tests)
python tests/e2e/test_pierce.py

# Trusted click on Turnstile (single bot)
python tests/e2e/test_trusted_click.py

# Multi-bot parallel test
python tests/e2e/multi_bot.py -n 2

# Fingerprint.com score test
python tests/e2e/test_fingerprint.py
```

## Profiles

Profiles are stored at `E:\chameleon_profiles\`. Each profile has a unique `chameleon_seed.txt` (128-bit hex, crypto-generated).

```bash
# Create a new profile
mkdir E:\chameleon_profiles\myprofile

# The seed is passed via command line, not stored in the profile dir
out\Default\chrome.exe --user-data-dir="E:\chameleon_profiles\myprofile" --chameleon-seed=$(python -c "import secrets; print(secrets.token_hex(16))")
```

## Build

```bash
# Incremental build (default, 16 threads)
build_chameleon.bat

# Full rebuild (runs gn gen first -- needed after .gn/.gni/args.gn changes)
build_chameleon.bat --full

# From bash shell
export DEPOT_TOOLS_WIN_TOOLCHAIN=0
/c/depot_tools/autoninja -C out/Default chrome -j 16
```

Build config: `out/Default/args.gn` — release build with `is_debug=false`, `is_component_build=true`, `symbol_level=0`.

## Architecture

### C++ Modifications

| File | What |
|------|------|
| `chameleon/chameleon_noise.h/.cc` | Central noise utility. Seed, FNV-1a hash, module enable check. |
| `chameleon/chameleon_binding.h/.cc` | `__chameleon` API injected in isolated worlds. Trusted click + deep query. |
| `element.cc` | `OpenShadowRoot()` — exposes closed shadows in isolated worlds only. |
| `binding_security.cc` | Cross-origin bypass in isolated worlds only. |
| `local_window_proxy.cc` | Hook to install `ChameleonBinding` on context creation. |
| `switches.h/.cc` | `--chameleon-seed`, `--chameleon-pierce`, etc. |
| `render_process_host_impl.cc` | Propagates chameleon flags to all renderer processes. |
