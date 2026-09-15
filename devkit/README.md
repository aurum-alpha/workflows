# The auth devkit

The configuration half of a working authentication tier: a Keycloak realm, an
nginx edge, an oauth2-proxy relying party, and the compose services that run
them. It is the route
[`solutions/060-auth.md`](../solutions/060-auth.md) names, wired to the port
offsets [`standards/016-local-development.md`](../standards/016-local-development.md)
LD4 fixes.

Every file here is a template. A product renders it once, commits the result
under `dev/`, and keeps the result equal to this source.

**The tree is `dev/` and not `deploy/`.** Every file in it is local
development: a dev realm, dev ports, one password every persona shares. It is
never deployed anywhere, and a directory named for deployment said the one
thing that is not true of it.

## Rendering

`devkit.json` at the repository root is the whole input, and it belongs to the
product rather than to this directory. It names the repository, its port block,
every service the gateway can reach, and where each path goes.

```json
{
  "repo": "credit-watch",
  "port_base": 2900,
  "upstreams": {
    "app": "server:5000",
    "client": "client:5173"
  },
  "routes": [
    { "exact":  "/healthz", "next": "app" },
    { "prefix": "/hooks/",  "next": "app" },
    { "prefix": "/api/",    "next": "auth", "then": "app" },
    { "prefix": "/",        "next": "auth", "then": "client", "no_session": "redirect" }
  ]
}
```

Render it, and re-render it after any change:

```sh
tools/render-devkit --target ../credit-watch
```

### The routing table is the whole of the product's routing

`edge.conf` holds the authentication tier's own endpoints and no others. There
is no built-in rule that `/` is a client and `/api/` is a server. That is an
architecture this directory has no business assuming. A monolith points
every upstream at one host. A product split into services points them at
several. The rendered gateway cannot tell the difference and does not try.

| Key | What it says |
|---|---|
| `tenant_hosts` | Optional. The labels a product with tenant hostnames serves locally, each as `<label>.localhost`. The realm admits a login callback on each beside the apex, and nothing else changes: the edge already answers on any host, and the relying party derives its callback from the host the browser is on (092 TH5). A product with one host leaves it out |
| `realm` | Optional, and one setting inside it: `{"registration": true}` lets people self-register at the provider, for a product whose users are whoever signs up rather than whoever was invited (AU4). Every other realm setting is the devkit's, the same in every product, and the renderer refuses any other key here |
| `upstreams` | A name the routes use, and the `host:port` behind it. The name is the product's; `auth` is reserved, because the devkit is what supplies that service |
| `next` | The hop this path goes to. Either `auth` or one of the product's upstreams |
| `then` | Where the authentication proxy forwards once it is satisfied. Required when `next` is `auth`, and meaningless otherwise |
| `no_session` | What a guarded route does when nobody is signed in: `401`, or `redirect` to send a browser to the login. Defaults to `401` |
| `exact` / `prefix` | The path, matched as nginx matches. A prefix of `/admin` also covers `/administrator`, so write `/admin/` when that matters |

**A route whose `next` is a service is handed over untouched.** No
`Authorization` line is set on it, so whatever the caller sent arrives intact.
That is the point. A webhook signature or an API key is a credential the
service must check, and it cannot check one the gateway threw away. Only a route the tier authenticated itself gets its `Authorization`
replaced, with the access token the relying party obtained (060 AU2).

**"Public" is not a category here.** A path anyone reaches with no credential
is a route handed to a service that requires nothing on it. A share
link and a webhook are handed straight over too, and both are authenticated,
just not by this tier. The gateway's only question is which hop
comes next.

**`devkit.json` is ingress configuration, and nothing else reads it.** Two
things open the file: `tools/render-devkit`, which turns it into the four
rendered files under `dev/`, and `tools/check-devkit-drift`, which renders it
again to compare bytes. No application process reads it, at startup, at build
time or in a test; it is not mounted into a container; no script derives
anything for the application from it. The `routes` above are nginx's hop
table and decide which paths pass through `auth_request`, and that is the
whole of what they decide. The application registers its own routes in its own
source, guards every one of them itself whatever hop the edge chose (060 AU9),
and proves that with its own route-coverage test. A product that generated a
route table, a guard list or a list of open paths from this file would have
made the gateway's table the application's, and the two are different tables
with different owners.

The renderer refuses each of these and names the entry:

- a path the template already declares
- a `next` that is neither `auth` nor a declared upstream
- a `then` on a route that is not guarded
- an upstream nothing routes to
- an address that is not `host:port`
- a port block that is not a multiple of twenty

Every problem in the file is reported at once.

### What is substituted, and how

| Placeholder | Value |
|---|---|
| `__REPO__` | The repository name, which is also the realm name |
| `__PORT_EDGE__` | base + 0, the edge, the address a person types |
| `__PORT_SERVER__` | base + 1, the API reached directly with a token |
| `__PORT_DB__` | base + 2, the database |
| `__PORT_IDP__` | base + 6, Keycloak |
| `__PORT_IDP_MGMT__` | base + 7, Keycloak's management and health port |
| `__UPSTREAMS__` | The upstream blocks, from `upstreams` |
| `__ROUTES__` | The locations, from `routes` |
| `"__REDIRECT_URIS__"`, `"__WEB_ORIGINS__"`, `"__POST_LOGOUT_REDIRECT_URIS__"` | The realm's three host lists: the apex and each `tenant_hosts` entry, as callback URIs, origins and post-logout targets. Quoted in the template so the source stays valid JSON |

The first six are textual substitution and nothing else, which is what lets a
drift checker render the source again and compare bytes. The rest are computed
from the record by the one renderer, and the drift checker computes them the
same way because it imports it.

It writes `dev/keycloak/realm.json`, `dev/nginx/edge.conf`,
`dev/oauth2-proxy/oauth2-proxy.cfg`, `dev/compose/auth.compose.yaml` and
`dev/tools/dev-token`. The compose fragment resolves the first three by
relative path, so the rendered tree keeps the shape of this one. A source that
is a command is rendered as one: the mode bits come across with the bytes.

**`ports.json` is not read here, and must not become the record.** A rendered
tree has to be checkable from a single clone.
[`../standards/016-local-development.md`](../standards/016-local-development.md)
says why, and a repository handed to a client has to keep passing after
nothing in this repository can see it. So the allocation lives in
`ports.json`, a person reads the base out of it once, and `devkit.json` carries
it from then on.

**The renderer is the only implementation of the substitution.**
[`../tools/check-devkit-drift`](../tools/check-devkit-drift) imports it rather
than repeating it. It renders into a scratch tree from the record and compares
bytes. Two renderers would drift, and the day they disagreed the drift checker
would be the thing certifying the drift.

Placeholders are substituted longest name first, so that `__PORT_IDP__`, a
prefix of `__PORT_IDP_MGMT__`, cannot eat the first half of the longer name.
The renderer then audits its own output for anything still matching `__NAME__`
and refuses to write a file carrying one. A placeholder added to a template
here, and not to the renderer, fails at the render rather than at the first
`nginx -t`.

## The files

| File | What it is |
|---|---|
| `keycloak/realm-template.json` | The realm import document: three clients, the access gate, and fifteen personas |
| `keycloak/personas.json` | What each persona is in the application, keyed by username; joined with the realm into the rendered `dev/personas.json` |
| `nginx/edge.conf` | The edge at offset +0, and the only routing table |
| `oauth2-proxy/oauth2-proxy.cfg` | The relying party behind `auth_request` |
| `compose/auth.compose.yaml` | The `edge`, `oauth2-proxy`, `keycloak`, `mail`, `migrate` and `seed` services |
| `compose/product.example.yaml` | The `db`, `server` and `client` services a product defines itself, and the `db` dependency it adds to the one-shots |
| `tools/dev-token` | Mints a persona's access token through the direct-grant client, for a terminal or a test |

One more file is rendered and has no template of its own: `dev/personas.json`,
the manifest the renderer joins from the realm template and
`keycloak/personas.json`. Subject, username, email, name, the identity's state
at the provider, and what the application's seed writes for it. It carries no
password: every persona's is `devkit-local-only`, `dev/tools/dev-token` knows
it, and a manifest of identities is not where a credential belongs.

## The three clients

| Client | What it is for |
|---|---|
| `__REPO__` | The confidential client oauth2-proxy runs as. It holds the tokens and owns the browser session |
| `__REPO__-admin` | The service-account client the application's control plane authenticates with, for the four provisioning operations of AU4 |
| `__REPO__-devtools` | A public direct-grant client, for local tooling that mints a persona's token without a browser |

The devtools client exists because a functional test wants a token and not a
login page. It is a local development client, and a rendered realm is never
deployed anywhere. `dev/tools/dev-token <persona>` is the command that uses it.

## What the realm file cannot say in itself

JSON carries no comments, so the reasoning behind its settings lives here.

**The two clients whose tokens reach the application mint RFC 9068 access
tokens for it.** `__REPO__` and `__REPO__-devtools` carry the
`access.token.header.type.rfc9068` attribute, so the header's `typ` is
`at+jwt`, and an audience mapper naming `__REPO__`, so `aud` names the
application's registration at the provider. Those are two of the five checks
AU2 makes a backend run, and a realm without them mints tokens every backend
refuses. The audience is the `__REPO__` client itself: it is the one
registration the application has at the provider, and the same registration
the access role below hangs off.

**No role mappers and no group mappers, anywhere.** AU2 keeps authorization
out of the token, and the RB rules put roles in the application. The mechanism
is two settings per client: `fullScopeAllowed` is false, and the `roles` scope
is absent from `defaultClientScopes`. Adding either back puts `realm_access`
into the token, and the application's access control then depends on provider
configuration. A realm shipping role mappers defeats the standard silently, so
this is not an omission to correct.

**The admin client is the one exception, and it is the opposite on both
settings.** Its service account carries `realm-management` roles, because
Keycloak's admin API authorizes from them, and Keycloak puts a role into a
token only where the client's scope admits it. So `__REPO__-admin` keeps the
`roles` scope and has `fullScopeAllowed` true, and the other two clients have
neither. Its token reaches Keycloak's admin API and nothing else, so the roles
in it govern the provider's control plane and never reach the application.
The roles are the four the control plane needs: `manage-users`, `view-users`
and `query-users` for the identity and its mappings, and `view-clients` to
resolve the application's client and read the access role.

**The provider enforces the access gate at login** (060 AU4). `__REPO__`
declares one client role, `access`, which is what `grantAppAccess` sets and
`revokeAppAccess` clears. The realm binds a flow to each of the two
application-facing clients: `__REPO__ browser` on the relying party and
`__REPO__ direct grant` on the devtools client. Each authenticates and then
runs a conditional sub-flow that denies an identity not holding
`__REPO__.access`. An identity without the role is refused on the login page,
and the direct grant answers `401` with the provider's error page rather than
a token. `dev/tools/dev-token` reads that page and prints its one line.

**The subject identifier type is public.** AU3 requires it, because a pairwise
subject differs per client for one human. Two applications behind one provider
then cannot tell they are looking at the same person. Keycloak makes a subject
pairwise through a dedicated protocol mapper, and no client here carries one.
The audience mapper above is a different mapper and changes nothing about
`sub`.

**The lifespans are AU5's numbers.** The token lives 300 seconds, the session
idles out after 28800, and it ends absolutely at 604800. `duplicateEmailsAllowed`
is false and `verifyEmail` is true, because AU3 keys provisioning on an address
that is unique and verified.

## The fifteen personas

Subject ids are fixed in the file. A test that logs in as a persona and asserts
on a subject cannot have that subject change per machine. Every persona
exercises exactly one refusal, or none, so a test that sees one knows which.
The realm holds identities and nothing else; what each persona is in the
application is `keycloak/personas.json`, and the two are rendered together
into `dev/personas.json` so that `tenant-a-admin` means the same rows in every
product. A persona named in one file and not the other refuses to render.

| Persona | Subject | Holds `access` | In the application | What it exercises |
|---|---|---|---|---|
| `platform-admin` | `aa000001-…-000000000001` | yes | admin at global | A grant that is global rather than inside one tenant |
| `tenant-a-admin` | `aa000002-…-000000000002` | yes | admin in tenant a | Administration inside one tenant |
| `tenant-b-admin` | `aa000003-…-000000000003` | yes | admin in tenant b | The same, in a second tenant, so isolation has two sides |
| `two-tenant-member` | `aa000004-…-000000000004` | yes | member in a and in b | AU8: one session acts in one tenant, and switching is an act on the session |
| `single-tenant-member` | `aa000005-…-000000000005` | yes | member in a | The ordinary case, where one grant is active without a choice |
| `no-application-access` | `aa000006-…-000000000006` | yes | no row | AU6: the provider admits the identity, the application does not know it, and it is refused and logged out. Under provider-is-source this is the first-login case instead, and the application writes the user |
| `deactivated-member` | `aa000007-…-000000000007` | yes | member in a | A disabled identity, refused at the provider |
| `unverified-email-member` | `aa000008-…-000000000008` | yes | member in a | An unverified address, refused at the login page and again at the proxy |
| `no-provider-access` | `aa000009-…-000000000009` | **no** | no row | AU4: an identity this application never granted access, refused by the provider's gate before any token exists |
| `tenant-a-operator` | `aa000010-…-000000000010` | yes | operator in a | The middle tier inside a tenant, so a product's role set has three rungs to check against |
| `tenant-a-member` | `aa000011-…-000000000011` | yes | member in a | The ordinary member of tenant a |
| `tenant-b-operator` | `aa000012-…-000000000012` | yes | operator in b | Tenant b's middle tier, mirroring a's |
| `tenant-b-member` | `aa000013-…-000000000013` | yes | member in b | The ordinary member of tenant b, reaching nothing in a |
| `user-one` | `aa000014-…-000000000014` | yes | member at global | A plain account, for a product with no tenants |
| `user-two` | `aa000015-…-000000000015` | yes | member at global | A second plain account, so one person's data can be shown to be nobody else's |

Personas 7 and 8 hold the role so that each trips its own refusal and not the
gate's. `admin`, `operator` and `member` are role classes, and a product maps
each onto its own role names (070 RB3); `a` and `b` are tenant labels a product
maps onto its own tenant ids, and `global` is `global`. A product with no
tenants reads the global grants and ignores the rest: its people are
`user-one`, `user-two` and `platform-admin`, and the tenant personas are
identities it never knows.

## Browser-facing against container-facing

Discovery is off in `oauth2-proxy.cfg`, and the endpoints are written out one
by one. A browser reaches Keycloak at `localhost:<base+6>`, and a container
reaches it at `keycloak:8080`. One discovery document cannot be right for both,
and resolving it would hand the backend an issuer string the token does not
carry.

| Setting | Which name it takes |
|---|---|
| `oidc_issuer_url` | Browser-facing |
| `login_url` | Browser-facing |
| `redeem_url` | Container-facing |
| `oidc_jwks_url` | Container-facing |
| `profile_url` | Container-facing |

Swapping those two halves is the classic failure here. The symptom is a login
that completes in the browser and then fails at the token exchange. An issuer
mismatch that reads as a bad signature is the other.

The compose fragment pins `KC_HOSTNAME` to the browser-facing name, so the
provider stamps one issuer string whichever address it was reached by.
`KC_HOSTNAME_BACKCHANNEL_DYNAMIC` keeps the container-facing URLs working
against that same realm.

**A backend has the same split, and its verifier is told both names.** The
token's `iss` is the browser-facing string, compared byte for byte. The key
set is fetched from the container-facing address,
`http://keycloak:8080/realms/<repo>/protocol/openid-connect/certs`. Every
platform module's `TrustedIssuer` takes the issuer and the JWKS URL as two
values for this reason. A verifier that discovered the key set from `iss`
would be asking `localhost` inside its own container. No proxy changes what
that name means there.

## Mail

The realm verifies email and offers a password reset, and both send mail.
`mail` is Mailpit. Every message the provider sends lands there, on SMTP at
offset +10, and is readable on its UI at `localhost:<base+11>`. Nothing
leaves the machine. Without it the provider answers a verification with a
500, because sending failed, instead of the page that says to check a
mailbox. That page is what `unverified-email-member` is for. Sign in as it,
open the UI, follow the link, and the persona is a verified member in tenant
a for the rest of that stack's life.

## The cookie

`__REPO__-session`, with `HttpOnly`, `SameSite=Lax` and `Path=/`.
`cookie_expire` is 604800 seconds, which is AU5's absolute maximum and the
same number the application reports as the session's expiry. `cookie_refresh`
sits inside the 300-second token lifespan, so the forwarded token is renewed
behind an unchanged cookie.

**It is plain and not `Secure`, and that is local development speaking, not
the standard.** 060 AU7 and 092 TH4 fix the production cookie as
`__Host-<name>`, `Secure` and host-only. This stack is plain HTTP on
`localhost` and `*.localhost`, where `Secure` protects nothing, and
oauth2-proxy forces `https` onto every derived callback while the cookie is
`Secure`, which nothing here serves. So the local cookie drops the attribute
and the prefix that requires it. Nothing about it reaches a deployment: the
production relying party is configured for its own hosts, and this file is
never deployed.

**There is no `cookie_domain`.** The browser scopes the cookie to the exact
host that set it, so a session made on `northwind.localhost` is never
presented to `contoso.localhost` or to the apex. That is TH4's host-only rule,
and it holds here without the prefix.

## Every host, one devkit

A product with tenant hostnames (092) runs the same rendered tree as a product
with one host. The edge's `server_name` is the catch-all, so it answers on
`localhost` and on every `*.localhost` name a browser resolves. The sign-in
redirect is relative, so a browser stays on the host it arrived on. The relying
party has no fixed `redirect_url` and derives the callback from the request
host, so a login begun on `northwind.localhost` lands its callback, and its
cookie, on `northwind.localhost`. And `/logout` returns the person to
`$http_host`. What a product with tenant hosts adds is the `tenant_hosts` list
in `devkit.json`, which puts each host into the realm's redirect, origin and
post-logout lists beside the apex, because the provider admits a callback only
on a host it was told about. A product with one host declares none and renders
today's realm.

## The edge

`auth_request /oauth2/auth` guards every path whose hop is `auth`. The relying
party answers the subrequest with both of the session's tokens: the access
token in the `X-Auth-Request-Access-Token` response header (`set_xauthrequest`
with `pass_access_token`) and the ID token as `Authorization: Bearer` on the
response (`set_authorization_header`). Each guarded location reads both with
`auth_request_set` and forwards both under the names 060 AU2 gives them:
`Authorization: Bearer $access_token`, the credential, RFC 9068's shape, which
the backend checks for `typ`, issuer, audience, signature and expiry; and
`X-Forwarded-Id-Token: $id_token`, the provider's statement about the
authentication event, which a backend refuses as a bearer on its `typ` and
reads only where its Conventions say so. A map strips the `Bearer` scheme off
the relying party's response header before the ID token is forwarded.

**A named capture in an nginx regex is a variable, everywhere.** The map's
capture is named `bare_id_token` and nothing else in the file shares the name.
A capture called `token` silently overwrote the `$token` that
`auth_request_set` had just filled with the access token, and every guarded
route forwarded the ID token twice.

**An inbound `Authorization` header never reaches a backend on a guarded
route.** Every location that proxies through the tier sets the header
explicitly. A guarded location sets it to the token from the subrequest. The
relying party's own locations set it to the empty string. The subrequest
location clears it too, because nginx passes the client's headers into the
subrequest by default. A route handed straight to a service sets no
`Authorization` line, so what the caller sent arrives intact for that service
to check.

**A `return 302 /path` is emitted as written.** `absolute_redirect` is off in
the server block, because nginx otherwise builds an absolute `Location` from
its own listen port. That port is 80 inside the container and not the block's
+0 on the host, so the sign-in redirect would send a browser to a port nothing
publishes.

That repetition is load-bearing. nginx drops every inherited `proxy_set_header`
inside a location that declares one of its own. A block written once at server
level would therefore vanish from exactly the locations that matter.

Five paths are the ones every product's table carries, each defined by a
standard as answerable before anyone is known. `/healthz` and `/readyz`
([`standards/030-service.md`](../standards/030-service.md) SC1),
`/config.json` and `/api/client-errors`
([`standards/090-web-client.md`](../standards/090-web-client.md) WC2 and WC5),
and `/.well-known/security.txt`
([`standards/085-security-baseline.md`](../standards/085-security-baseline.md)
SB7). They are routes like any other. A product split into services might
serve them from somewhere other than its API, and this directory cannot know
which.

`/logout` is the RP-initiated logout of AU5 in one hop. It ends the proxy
session and then sends the browser to the provider's end-session endpoint,
naming the host the person was on as the place to return to. Ending only the
first leaves the provider session alive, and the next sign-in click signs the
person straight back in.

The API is also published at offset +1, which is how a developer reaches it
directly with a token. That path skips the edge by design. It is safe because
AU2 makes the backend verify the token for itself. The `typ` header, the
issuer, the audience, the signature and the expiry are all checked there.

## What the product supplies

The fragment defines five services and expects the product to define the
services its routing table names, plus whatever database it has:

| Service | Who defines it |
|---|---|
| `edge`, `oauth2-proxy`, `keycloak`, `migrate`, `seed` | The fragment |
| `server`, `client`, and `db` where there is one | The product, in its own `compose.yaml` |

The two one-shots run the product's own commands. `tools/migrate` applies the
identity tables, and `tools/seed-personas` writes the application-side user and
grant rows the realm's personas correspond to, reading `dev/personas.json` for
which rows those are: a row for every persona whose `application.user` is true,
and a grant for each entry of its `application.grants`, with the product's own
role name for the role class and its own tenant id for the label. Both are
idempotent, both exit, and `docker compose up` runs them in order before
anything serves.

**The one-shots depend on no database in the fragment.** The fragment does not
know whether the product has one: a product on SQLite migrates a file. A
product with a `db` service adds `depends_on: db` to `migrate` and `seed` in
its own `compose.yaml`, which is what `product.example.yaml` shows, so `up`
orders them after it.

## Checking a change

Compose validates port numbers, so both commands run against a rendered tree
rather than against the templates.

```sh
docker compose -f dev/compose/auth.compose.yaml \
               -f dev/compose/product.example.yaml config

python3 -c "import json; json.load(open('dev/keycloak/realm.json'))"

tools/check-devkit-nginx
```

**A change to the realm, the relying party or the edge is proved on the
running stack, never by reading it.** Render into a scratch tree whose
upstream echoes its request headers, with two `tenant_hosts` declared,
`docker compose up`, and then: log a persona in through the edge on the apex
and on each tenant host (`curl --resolve <host>:<port>:127.0.0.1`), and read
the `Authorization` header the upstream received and the host the cookie was
set for; sign out on a tenant host and see the return land there; decode the token and check `typ` is `at+jwt`, `aud` names the realm's
client and `sid` is present; mint the same persona through
`dev/tools/dev-token`; log `no-provider-access` in and see the provider's
refusal with no callback reached; mint `deactivated-member` and
`unverified-email-member` and see each refused for its own reason; and, with
a client-credentials token for `__REPO__-admin`, read the application's client
and its `access` role, grant it to `no-provider-access`, mint a token, revoke
it, and see the refusal return. Keycloak's permission model is easy to be one
setting wrong about, and a realm that imports without error can still mint a
token every backend refuses.
