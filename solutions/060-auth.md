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
| The token | The provider's RFC 9068 access token, audience-scoped to the backend | AU2 admits one form. The proxy obtains it and forwards it; nothing at the edge signs anything. |

That edge is the `oauth2-proxy` row below. It sits behind nginx's
`auth_request` rather than in front of the API. nginx stays the one routing
table, and oauth2-proxy answers the subrequest.

**Signature verification is a backend obligation on this route**. Each backend
runs AU2's five checks against the provider's JWKS: the `typ` header, the
issuer, the audience, the signature and the expiry. A backend that decodes
without verifying is an unauthenticated service.

**oauth2-proxy puts the ID token in `Authorization` and the access token in
`X-Forwarded-Access-Token`**. AU2's token is the access token, so a backend on
this route reads that header. Carrying the access token in `Authorization` is
an open request upstream. AU2 asks the repository to name the header it uses
in its **Conventions**, and this is the route that needs it named.

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
| An edge proxy's built-in OIDC filter | The service mesh or ingress | Verify that it holds the tokens and forwards the provider's access token, audience-scoped to the backend. A filter forwarding the ID token to an API is refused by AU2. |

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
2. **Whether `sub` survives a change of connection.** This is the same failure
   arriving by a different route, and it separates the providers checked here.
   Keycloak's subject is its own user record's, so brokering an upstream
   provider does not move it. **Auth0's subject embeds the connection**:
   `google-oauth2|1234` against `auth0|5678`. A person who signed in with a
   password and later signs in with a social login is a second subject and a
   second account. Auth0's account linking is a deliberate API call, never
   automatic. A product admitting more than one connection per person plans
   for that before the first duplicate.
3. **Which fields the provider masters, and which it lets the application
   write** (AU10). A brokered upstream provider masters what its mapper syncs.
   A mapper set to overwrite on every login makes an application write
   disappear at the next sign-in. Keycloak's identity-provider mappers carry a
   sync mode for this, and `force` is the one that overwrites.
4. **Email uniqueness is enforced on the verified address, and you know where
   the setting lives.** In Keycloak it is the realm's duplicate-emails
   setting. The equivalent exists elsewhere under other names, and it is
   frequently *off* by default. AU4 depends on it.
5. **Whether SCIM provisioning is first-party or an extension.** This differs
   sharply between providers and is the item most often assumed rather than
   checked. It matters only for AU4's provider-is-source mode, where an HR or
   identity-governance system owns the workforce lifecycle and provisions
   into the provider.
6. **Whether the provider can issue a JWT access token at all**. AU2 does not
   admit a provider that issues only opaque tokens. Reading one takes a call
   to the provider on every request, which AU1 forbids. This is a selection criterion, so
   it is checked before the rest of this list matters.
7. **Whether the provider emits RFC 9068 access tokens, and how it is
   switched on**. AU2 pins the `typ` header to `at+jwt`, and a resource server
   rejects any other value. In Keycloak this is the client setting *Use
   'at+jwt' as access token header type*, and it is **off by default** for
   backward compatibility.
8. **Whether the provider restricts the audience, and by which mechanism.**
   AU2 wants the backend's resource indicator in `aud`. Either RFC 8707's
   `resource` parameter or a provider audience mapper reaches it. Keycloak
   uses an Audience protocol mapper on the client.
9. **Whether `sid` reaches the access token**, and only where the product
   lets a person hold more than one grant in one tenant. RFC 9068 defines no
   `sid`. AU8 admits the relying party's own session identifier instead, so
   a provider withholding `sid` rules out one source and not the rule.
10. **Whether back-channel logout is supported**, for AU5's revocation not
   waiting on session expiry. **The default route above does not support it**,
   whatever the provider offers: oauth2-proxy has no back-channel logout
   endpoint for a provider to post to. On that route AU5's revocation rests on
   the short token lifetime, which is the backstop AU5 names for exactly this
   case.

## Refused, and the rule that refuses each

| Route | Refused by |
|---|---|
| An OIDC library linked into the application as the authentication chain | **AU1**, which admits an application-code BFF only where the repository states the reason in **Conventions** and accepts AU7's costs. |
| A token the backend decodes and does not verify | **AU2**, which requires the `typ` header, the issuer, the audience, the signature and the expiry to be checked. A parsed token is no check at all. |
| The provider's ID token forwarded as a bearer to an API | **AU2** and RFC 9068 section 4. An ID token asserts who authenticated to a client, carries no audience for the backend, and is rejected on its `typ`. |
| A bespoke identity token the proxy mints for the internal hop | **PC2**. RFC 9068 fixes the shape, RFC 8707 and RFC 9700 restrict the audience, and RFC 8693 puts the minting at the authorization server. |
| Plain injected headers, with or without network isolation | **AU2**, which admits one form. An unsigned header rests an authentication guarantee on a topology property nobody writes down. |
| Roles or groups read from the provider's token to decide access | **070 RB1** and 060's own boundary: the provider supplies identity, never authorization. |
| The email address used as the application's key for a person | **AU3**. The link is on `sub`; an email change must cost nothing. |
