# Acceptable solutions: authentication

Register for [`standards/060-auth.md`](../standards/060-auth.md).

060 fixes the shape (AU1, AU7) and leaves the proxy module and the identity
provider to the platform.

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
   checked. It matters only for AU4's third case, where an HR or
   identity-governance system owns the workforce lifecycle and provisions
   into the provider.
4. **Whether back-channel logout is supported**, for AU5's revocation not
   waiting on session expiry.

## Refused, and the rule that refuses each

| Route | Refused by |
|---|---|
| An OIDC library linked into the application as the authentication chain | **AU1**, which admits an application-code BFF only where the repository states the reason in **Conventions** and accepts AU7's costs. |
| The provider's access token passed through to the backend | **AU2**. One signed identity token crosses the proxy, minted by the tier. |
| Roles or groups read from the provider's token to decide access | **070 RB1** and 060's own boundary: the provider supplies identity, never authorization. |
| The email address used as the application's key for a person | **AU3**. The link is on `sub`; an email change must cost nothing. |
