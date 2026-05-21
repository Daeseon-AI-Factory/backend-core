# identity v3 — oauth

## Where we are

- **Previous version:** `services/identity/v2-performance/`
- **Next version:** `v4-mfa.md`

## Motivation — what v2 fails at

v2 only supports email + password. Real users (and especially developer-tool users) expect "Sign in with Google" and "Sign in with GitHub":

- Password-only increases support cost (forgotten passwords, manual resets)
- Adds friction at signup that measurably hurts conversion
- Misses the segment of users who already have OAuth-provider accounts and don't want yet another password

OAuth2 also unlocks downstream features: the integration service can later request additional Google scopes for the same user without re-onboarding.

## What v3 adds

### Spring Security OAuth2 Client

Library: `org.springframework.boot:spring-boot-starter-oauth2-client` (already covers everything needed — no separate library per provider).

Providers configured: Google + GitHub.

### Configuration

```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          google:
            client-id: ${GOOGLE_CLIENT_ID}
            client-secret: ${GOOGLE_CLIENT_SECRET}
            scope: openid,email,profile
            redirect-uri: "{baseUrl}/login/oauth2/code/{registrationId}"
          github:
            client-id: ${GITHUB_CLIENT_ID}
            client-secret: ${GITHUB_CLIENT_SECRET}
            scope: read:user,user:email
            redirect-uri: "{baseUrl}/login/oauth2/code/{registrationId}"
        provider:
          google:
            # google is a built-in CommonOAuth2Provider; this block can be omitted in practice
            authorization-uri: https://accounts.google.com/o/oauth2/v2/auth
            token-uri: https://oauth2.googleapis.com/token
            user-info-uri: https://openidconnect.googleapis.com/v1/userinfo
            user-name-attribute: sub
          github:
            authorization-uri: https://github.com/login/oauth/authorize
            token-uri: https://github.com/login/oauth/access_token
            user-info-uri: https://api.github.com/user
            user-name-attribute: id
```

GitHub's user-info doesn't always return email if the user has set it private. Handle this by making a follow-up call to `https://api.github.com/user/emails` (requires the `user:email` scope) and using the primary verified email.

### Endpoints

Spring Security auto-generates the OAuth2 dance endpoints; we provide our own callbacks plus account-management endpoints.

| Method | Path | Behavior |
|---|---|---|
| GET | `/oauth2/authorization/google` | Spring auto: 302 to Google's authorize URL |
| GET | `/oauth2/authorization/github` | Spring auto: 302 to GitHub's authorize URL |
| GET | `/login/oauth2/code/{registrationId}` | Spring auto: handles the callback; we customize success handler to (1) look up or create local user (2) issue our own JWT pair (3) redirect to a configurable success URL with the access token in a fragment (`#access_token=...`) |
| GET | `/me/providers` | Auth required. Returns linked providers for the current user: `{ "providers": ["password","google"] }` |
| POST | `/me/providers/{provider}` | Auth required. Initiates the linking flow (returns 302 to OAuth provider with state including the existing user id) |
| DELETE | `/me/providers/{provider}` | Auth required. Unlinks a provider. Must leave at least one auth method on the account (password or another OAuth provider); else 409. |

### Account linking logic

On the OAuth2 success handler:

1. Extract the provider-supplied email (verified) and provider user id
2. Look up `oauth_identities` by `(provider, provider_user_id)`:
   - **Match:** load that user, issue our JWT pair
3. If no match, look up `users` by email:
   - **Match (email-matched):** insert a new row into `oauth_identities` linking this provider to the existing user (no password required — the OAuth provider proves email control). Issue JWT pair.
   - **No match:** create a new row in `users` with `password_hash = NULL`; insert into `oauth_identities`; issue JWT pair.
4. If the email returned by the provider is NOT marked verified by the provider, do NOT auto-link to an existing email match — instead require explicit linking flow (returns 409 with a code the user can verify).

A user with `password_hash = NULL` cannot use password login (returns the standard "invalid credentials" — does not reveal "this is OAuth-only").

### Data model changes

```sql
-- V4__oauth.sql
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

CREATE TABLE oauth_identities (
  id               BIGSERIAL PRIMARY KEY,
  user_id          BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider         VARCHAR(32)  NOT NULL,
  provider_user_id VARCHAR(255) NOT NULL,
  email_verified   BOOLEAN      NOT NULL DEFAULT FALSE,
  linked_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (provider, provider_user_id)
);

CREATE INDEX idx_oauth_identities_user ON oauth_identities(user_id);
```

### Dependencies

```kotlin
dependencies {
  // ... everything from v2 ...
  implementation("org.springframework.boot:spring-boot-starter-oauth2-client")
}
```

## What v3 does NOT add

- SAML / enterprise SSO → that belongs in the `organization` service (`organization v4`), bound at the org level, not the user level
- Passwordless / magic-link → out of scope
- MFA → v4
- Hardening (constant-time enumeration prevention beyond v2, lockout, etc.) → v6

## Done criteria

1. v2's password flow still works (including k6 baseline still passing)
2. With valid Google credentials configured in env:
   - GET `/oauth2/authorization/google` redirects to Google
   - After Google auth, callback issues a local JWT pair
   - `GET /me` with that JWT returns the user
3. Same flow with GitHub credentials
4. Account linking: a password-existing user logs in with Google whose email matches → `GET /me/providers` returns `["password","google"]`
5. OAuth-only user (created via Google, no password set) attempts password login → standard 401 (does NOT reveal that the account is OAuth-only)
6. Unverified email from provider → linking blocked, 409 with explanatory code
7. DESIGN.md includes:
   - The OAuth2 authorization-code flow in text-based sequence form
   - The account-linking decision tree
   - The "what if provider says unverified" edge case
   - A note on local-dev OAuth setup (link to Google Cloud Console / GitHub OAuth Apps)

## Local dev OAuth setup

For Google: https://console.cloud.google.com/ → create OAuth 2.0 Client ID → Web application → authorized redirect URI `http://localhost:8104/login/oauth2/code/google`.

For GitHub: https://github.com/settings/developers → New OAuth App → callback URL `http://localhost:8104/login/oauth2/code/github`.

If the user lacks credentials, the password flow still works; OAuth endpoints will return errors. DESIGN.md must note this gracefully-degraded mode.

## Compose overlay

`infra/compose/overlays/identity-v3.yml`:

```yaml
services:
  identity-v3:
    build:
      context: ../../../
      dockerfile: services/identity/v3-oauth/Dockerfile
    image: identity-v3:local
    ports:
      - "8104:8104"
    environment:
      DB_HOST: postgres
      DB_USER: postgres
      DB_PASSWORD: postgres
      JWT_SECRET: dev-only-secret-please-change-this-is-at-least-32-bytes
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID:-}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET:-}
      GITHUB_CLIENT_ID: ${GITHUB_CLIENT_ID:-}
      GITHUB_CLIENT_SECRET: ${GITHUB_CLIENT_SECRET:-}
    depends_on:
      postgres:
        condition: service_healthy
```

The `:-` syntax means "default to empty if unset" — the service starts even without OAuth credentials; OAuth endpoints will just be non-functional until credentials are provided.

## Claude Code prompt

```
Build identity v3-oauth.

Read service-plans-v2/identity/v3-oauth.md. Look at services/identity/v2-performance/ for v2's structure. Re-implement v2's functionality in a new module services/identity/v3-oauth/ with Spring Security OAuth2 Client added for Google and GitHub providers.

Copy v2's Flyway migrations V1, V2, V3 into the new module unchanged; ADD V4__oauth.sql per the spec.

Implement a custom AuthenticationSuccessHandler that performs the account-linking logic described in the spec ("Account linking logic" section). The handler must NOT auto-link if the provider reports the email as unverified.

For GitHub: when /user does not return an email, call /user/emails and use the primary verified email.

Configuration per the spec. OAuth credentials read from env vars and may be empty in local dev (service still starts; OAuth endpoints non-functional).

Database: identity_v3. Port: 8104. Compose overlay per the spec.

Do NOT add MFA, observability, or hardening features. Do NOT modify earlier versions. Do NOT run git commit.

Stop when the done criteria are met. If GOOGLE_* / GITHUB_* env vars are not set, the OAuth-flow done criteria are unverifiable in local dev — note this in DESIGN.md and verify what you can (password flow, /me/providers for password-only user).
```
