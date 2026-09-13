# Acceptable solutions: authentication

Register for [`standards/060-auth.md`](../standards/060-auth.md). Routes here
were checked against it on 2026-09-13.

060 fixes the shape (AU1, AU7) and leaves the proxy module and the identity
provider to the platform.

## The default route

A repository with no reason to choose otherwise takes this one.

| Choice | The route | Why |
|---|---|---|
| The edge | **nginx**, with **oauth2-proxy** behind `auth_request` | One routing table serves the static files, a client development server and a backend in any language. The relying party stays one job behind that table, so a second backend is a new upstream rather than a second authentication implementation. |
| The token | **AU2 form (a)**: the provider's ID token, forwarded as `Authorization: Bearer` | No off-the-shelf proxy mints form (b)'s intermediary token, so form (b) here would be first-party code in the tier AU1 exists to keep free of it. |

That edge is the `oauth2-proxy` row below. It sits behind nginx's
`auth_request` rather than in front of the API. nginx stays the one routing
table, and oauth2-proxy answers the subrequest.

**Form (a) makes signature verification a backend obligation rather than a
proxy guarantee**. Under form (b) the tier is the only thing that signs, and a
backend trusts one key. Under form (a) each backend verifies the signature, the
issuer, the audience and the expiry against the provider's JWKS. A backend that
decodes without verifying is an unauthenticated service. AU2 says so for
both admitted forms, and this route is the one where it is load-bearing.

**The development configuration is split-horizon, and that breaks discovery**.
The browser reaches the provider at one host. A backend inside the network
reaches its JWKS at another. Discovery would resolve one of those two and hand
the backend an issuer string that does not match the token. So discovery is off,
the issuer string is configured and compared byte for byte, and the JWKS URL is
set explicitly. The two hosts name one provider, and only the configuration says
so.

## The proxy's OIDC module (AU1, AU7 topology B1)

These modules deliver AU1's edge authentication with no first-party code.

| Module | Sits in | Notes against 060 |
|---|---|---|
| `mod_auth_openidc` | Apache httpd | The longest-standing of these; an OpenID Connect relying party as an Apache module. |
| `lua-resty-openidc` | OpenResty, or nginx built with the Lua module | **Verify the build first.** Stock open-source nginx does not run it; a platform standardised on plain nginx is choosing a different row, not this one. |
| `oauth2-proxy` | Its own process, in front of the API | A standalone proxy rather than a module, which suits a platform whose edge is not one of the two above. Still AU7's B1 shape: the OAuth client is at the edge and the API server is not internet-facing. |
| An edge proxy's built-in OIDC filter | The service mesh or ingress | Verify that it holds the tokens and mints AU2's identity token rather than passing the provider's token through, which is the failure AU2 exists to prevent. |

## The identity provider (AU3, AU4, AU6)

The provider is a platform choice, so this page carries a checklist rather
than a ranking.

Checked: **Keycloak**, **Auth0**, **Okta**, **Microsoft Entra ID**,
**AWS Cognito**, **Ory Hydra**, **Authentik**, **Zitadel**. Each is an OIDC
provider, the interface 060 binds, and the rules do not distinguish between
them.

What to verify on any of them, in this order:

1. **The subject identifier type is `public` and `sub` is stable.** AU3 keys
   the application's link on `sub`. A provider configured for pairwise
   subjects, or one that mints a new `sub` when an account is re-created,
   breaks the link silently. The application then sees AU6's unknown subject.
2. **Email uniqueness is enforced on the verified address, and you know where
   the setting lives.** In Keycloak it is the realm's duplicate-emails
   setting. The equivalent exists elsewhere under other names, and it is
   frequently *off* by default. AU4 depends on it.
3. **Whether SCIM provisioning is first-party or an extension.** This differs
   sharply between providers and is the item most often assumed rather than
   checked. It matters only for AU4's provider-is-source mode, where an HR or
   identity-governance system owns the workforce lifecycle and provisions
   into the provider.
4. **Whether back-channel logout is supported**, for AU5's revocation not
   waiting on session expiry. **The default route above does not support it**,
   whatever the provider offers: oauth2-proxy has no back-channel logout
   endpoint for a provider to post to. On that route AU5's revocation rests on
   the short token lifetime, which is the backstop AU5 names for exactly this
   case.

## Refused, and the rule that refuses each

| Route | Refused by |
|---|---|
| An OIDC library linked into the application as the authentication chain | **AU1**, which admits an application-code BFF only where the repository states the reason in **Conventions** and accepts AU7's costs. |
| A token the backend decodes and does not verify | **AU2**, which requires the signature, the expiry and key rotation to be checked on both admitted forms. A parsed token is no check at all. |
| Plain injected headers, with no network isolation stated and enforced | **AU2** form (c). An unsigned header rests an authentication guarantee on a topology property, and that property is usually written down nowhere. |
| Roles or groups read from the provider's token to decide access | **070 RB1** and 060's own boundary: the provider supplies identity, never authorization. |
| The email address used as the application's key for a person | **AU3**. The link is on `sub`; an email change must cost nothing. |
