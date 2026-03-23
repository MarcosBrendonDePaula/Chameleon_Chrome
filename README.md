# Chameleon Browser

Privacy-focused browser based on Chromium.

## Base

Built on top of Chromium `main` branch. Patches are applied on top of the upstream source.

## Setup

1. Clone and sync Chromium source: https://chromium.googlesource.com/chromium/src.git
2. Apply patches:
   ```bash
   git am patches/*.patch
   ```
3. Build:
   ```bash
   build_chameleon.bat
   ```
4. Run:
   ```bash
   run_chameleon.bat
   ```

## Patches

- `0001-feat-allow-off-store-extension-installation.patch` - Enable off-store extension installation

## Chromium Base Commit

```
9760e6c70c Roll Chrome Mac PGO Profile
```
