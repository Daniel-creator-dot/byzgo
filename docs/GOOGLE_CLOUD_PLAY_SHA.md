# Google Cloud — Play release SHA-1 (copy into Console)

Package: **`net.bytzgo.app`**

## Release keystore (Play AAB)

| Field | Value |
|-------|--------|
| SHA-1 | `B2:A0:44:C8:79:A5:97:50:95:AB:9A:C5:B6:0A:2F:FD:7C:DE:3F:2D` |
| SHA-256 | `E9:8F:20:D0:1D:D4:5A:6A:E3:D1:38:0D:7B:3B:01:6D:E1:78:3C:90:3F:F9:15:83:4C:BD:D3:29:D9:EF:A0:09` |

## Where to add (5 minutes)

1. [Firebase](https://console.firebase.google.com/project/bytzgo-9bd89/settings/general) → Your apps → Android **net.bytzgo.app** (add app if missing) → **Add fingerprint** → paste SHA-1 above → download new `google-services.json` if offered.

2. [Google Cloud Credentials](https://console.cloud.google.com/apis/credentials?project=bytzgo-9bd89) → **Create credentials** → **OAuth client ID** → **Android** → package `net.bytzgo.app` + SHA-1 above (or edit existing Android client).

3. **Maps API key** (same project) → Edit key → Application restrictions → Android apps → add `net.bytzgo.app` + SHA-1.

Re-run locally:

```powershell
cd mobile
.\scripts\print_release_sha1.ps1
```
