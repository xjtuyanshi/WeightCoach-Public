# Security

## Private configuration

Do not commit any of the following:

- `WeightCoach/BridgeConfigLocal.plist`
- API keys, access tokens, passwords, cookies, or login sessions
- private bridge or Tailscale URLs
- Apple Health exports, real body measurements, device logs, or user photos

The iPhone app must not contain a cloud AI API key. Configure AI recognition
only through a bridge you control, and never expose an unauthenticated bridge
to the public internet.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub Security Advisories
instead of opening a public issue. Include reproduction steps and the affected
commit, but do not attach real health data, credentials, or private service
addresses.
