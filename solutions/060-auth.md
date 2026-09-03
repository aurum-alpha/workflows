# Acceptable solutions: authentication

The acceptable solutions register for
[`060-auth.md`](../standards/060-auth.md). It is not a standard and states no
rule — read
[the charter](../README.md#acceptable-solutions-the-register-of-what-satisfies-a-standard)
for what this class of document may and may not do. Everything below is a
claim that some component satisfies a rule 060 states, and the date that claim
was last checked.

060 decides the shape and leaves the component open: AU1 puts authentication
in a tier in front of the application, AU7 admits three topologies, and the
identity provider is a backing service throughout. What it never decides is
which proxy module or which provider, because those are chosen by what a
platform already runs.

## The proxy's OIDC module (AU1, AU7 topology B1)

AU1 prefers the proxy because the capability then arrives as configuration
rather than as a runtime to maintain. These are the modules that deliver it
with no first-party code:

| Module | Sits in | Notes against 060 |
|---|---|---|
| `mod_auth_openidc` | Apache httpd | The longest-standing of these; an OpenID Connect relying party as an Apache module. |
| `lua-resty-openidc` | OpenResty, or nginx built with the Lua module | **Verify the build first.** Stock open-source nginx does not run it; a platform standardised on plain nginx is choosing a different row, not this one. |
| `oauth2-proxy` | Its own process, in front of the API | A standalone proxy rather than a module, which suits a platform whose edge is not one of the two above. Still AU7's B1 shape: the OAuth client is at the edge and the API server is not internet-facing. |
| An edge proxy's built-in OIDC filter | The service mesh or ingress | Verify that it holds the tokens and mints AU2's identity token rather than passing the provider's token through, which is the failure AU2 exists to prevent. |

Whichever row, the thing to check is AU2: the module terminates the
authentication chain and what crosses to the backend is the platform's own
signed identity token, not the provider's access token.

## The identity provider (AU3, AU4, AU6)

The register names no default. The provider is a platform choice, and the
rules that matter are the same for all of them — so this page carries the
checklist rather than a ranking.

Checked and in use across the common cases: **Keycloak**, **Auth0**,
**Okta**, **Microsoft Entra ID**, **AWS Cognito**, **Ory Hydra**,
**Authentik**, **Zitadel**. Each is an OIDC provider; that is the interface
060 binds, and the standard's rules do not distinguish between them.

What to verify on any of them, in this order:

1. **The subject identifier type is `public` and `sub` is stable.** AU3 keys
   the application's link on `sub`. A provider configured for pairwise
   subjects, or one that mints a new `sub` when an account is re-created,
   breaks the link silently and the application sees AU6's unknown subject.
2. **Email uniqueness is enforced on the verified address, and you know where
   the setting lives.** In Keycloak it is the realm's duplicate-emails
   setting; the equivalent exists elsewhere under other names, and it is
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

## Checked

**2026-09-03**, against each project's own documentation. Next re-check due
**2027-03-02**, per the charter's 180-day horizon. A re-check confirms each
module still exists under that name and still terminates the chain at the
edge, and that the four verification items still name settings that exist. A
provider dropping `public` subject identifiers, or making pairwise the only
option, would be a finding against AU3 and belongs back in the standard rather
than on this page.
