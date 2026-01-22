# External Integrations

**Analysis Date:** 2026-01-21

## APIs & External Services

**Payment Processing:**
- Not detected

**Email/SMS:**
- Not detected

**External APIs:**
- Not detected (no `URLSession` usage in app sources; app appears local-only)

## Data Storage

**Databases:**
- Not detected

**File Storage:**
- Local filesystem - user-selected folders enumerated to find images (`AppState.swift`)

**Caching:**
- Not detected (no explicit `NSCache` or other caches in app sources)

## Authentication & Identity

**Auth Provider:**
- Not detected

**OAuth Integrations:**
- Not detected

## Monitoring & Observability

**Error Tracking:**
- Not detected

**Analytics:**
- Not detected

**Logs:**
- Not detected (no logging framework; minimal/no `print` usage in app sources)

## CI/CD & Deployment

**Hosting:**
- Not applicable (desktop app)

**CI Pipeline:**
- Not detected (no `.github/workflows/*`)

**Local build pipeline:**
- XcodeGen project generation + Xcode build (`build.sh`, `project.yml`)
- Ad-hoc local code signing for `.app` output (`build.sh`)

## Environment Configuration

**Development:**
- No required environment variables detected
- Folder access prompts configured via usage strings (`Info.plist`)

**Staging:**
- Not applicable

**Production:**
- Not detected (no release automation / notarization config)

## Webhooks & Callbacks

**Incoming:**
- Not applicable

**Outgoing:**
- Not applicable

---

*Integration audit: 2026-01-21*
*Update when adding/removing external services*
