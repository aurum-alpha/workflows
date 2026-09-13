# The fleet auth devkit

The configuration half of a working authentication tier: a Keycloak realm, an
nginx edge, an oauth2-proxy relying party, and the compose services that run
them. It is the route
[`solutions/060-auth.md`](../solutions/060-auth.md) names, wired to the port
offsets [`standards/016-local-development.md`](../standards/016-local-development.md)
LD4 fixes.

Every file here is a template. A product renders it once, commits the result
under `deploy/`, and keeps the result equal to this source.

## Rendering

Three inputs decide everything: the repository name, the block base recorded
for that repository in [`../ports.json`](../ports.json), and the container-side
port the API binds. The base is a multiple of twenty, and every port below is
the base plus the offset LD4 fixes for that role.

| Placeholder | Value |
|---|---|
| `__REPO__` | The repository name, which is also the realm name |
| `__PORT_EDGE__` | base + 0, the edge, the address a person types |
| `__PORT_SERVER__` | base + 1, the API reached directly with a token |
| `__PORT_DB__` | base + 2, the database |
| `__PORT_IDP__` | base + 6, Keycloak |
| `__PORT_IDP_MGMT__` | base + 7, Keycloak's management and health port |
| `__SERVER_PORT__` | The container-side port the API binds, which is its LD1 default |

Substitution is textual and nothing else. That is what lets a drift checker
render the source again and compare a rendered tree against this one.

[`../tools/render-devkit`](../tools/render-devkit) does it. Adopt once, naming
the three inputs:

```sh
tools/render-devkit --target ../credit-watch \
                    --repo credit-watch --base 2900 --server-port 5000
```

It writes `deploy/keycloak/realm.json`, `deploy/nginx/edge.conf`,
`deploy/oauth2-proxy/oauth2-proxy.cfg` and
`deploy/compose/auth.compose.yaml`. The compose fragment resolves the other
three by relative path, so the rendered tree keeps the shape of this one.

It also writes `deploy/devkit.json`, which records the three inputs. After
that the target re-renders from its own record and takes no arguments:

```sh
tools/render-devkit --target ../credit-watch
```

**That record is why `ports.json` is not read here.** A rendered tree has to be
checkable from a single clone —
[`../standards/016-local-development.md`](../standards/016-local-development.md)
says why, and a repository handed to a client has to keep passing after nothing
in this repository can see it. So the allocation lives in `ports.json`, a person
reads the base out of it once, and the rendered tree carries it from then on.

**The renderer is the only implementation of the substitution.**
[`../tools/check-devkit-drift`](../tools/check-devkit-drift) imports it rather
than repeating it, renders into a scratch tree from the record, and compares
bytes. Two renderers would drift, and the day they disagreed the drift checker
would be the thing certifying the drift.

### The product's own public paths

[`../standards/060-auth.md`](../standards/060-auth.md) AU9 has each product
declare once which paths need no login, in `deploy/public.json`, and has both
the ingress and the application read it. The renderer is the ingress half.
When the target carries the file, its entries are rendered into `edge.conf`
in place of the `__ROUTES__` line. When it does not, that line is dropped
whole. So a product that declares nothing renders byte for byte what it did
before. The file is the product's own, never rendered and never checked for
drift.

```json
{
  "schema_version": 1,
  "public": [
    { "prefix": "/events/", "upstream": "server" },
    { "exact":  "/pricing", "upstream": "client" }
  ],
  "pages": [
    { "exact":  "/",      "upstream": "server" },
    { "prefix": "/admin", "upstream": "server" }
  ]
}
```

| Key | Who reads it | Renders as |
|---|---|---|
| `public` | the ingress and the application | a location with no `auth_request` and `Authorization ""`, to the named upstream |
| `pages` | the ingress only | a location with `auth_request` and `error_page 401 = @sign_in`, to the named upstream |

`exact` renders `location = /x`; `prefix` renders `location /x` and matches
as nginx matches, so `/admin` also covers `/administrator`. Write `/admin/`
when that matters. `upstream` is `server` or `client`, the two the fragment
defines. A `client` upstream also gets the upgrade headers, because the dev
server's hot-reload socket rides the same location.

`pages` exists for a product whose backend renders its own authenticated
pages. The template sends `location /` to the client, and a prefix location
beats it. Naming `/admin` here moves that page to the backend without
touching the shared file. A product with the SPA on `/` needs nothing in it.

The renderer refuses what nginx would refuse or what the rule forbids, and
names the entry. Refused: a path the template already declares in the same
form, a prefix of `/`, an upstream the fragment does not define, a pattern. A product
with no login at all runs no edge; its `public.json` still says so for the
application's benefit, and it is not rendered.

[`public.example.json`](nginx/public.example.json) is the sample
[`../tools/check-devkit-nginx`](../tools/check-devkit-nginx) renders with. So
the locations this emits are parsed by the pinned nginx on every run, not
only the template's own.

Placeholders are substituted longest name first, so that
`__PORT_IDP__` — a prefix of `__PORT_IDP_MGMT__` — cannot eat the first half of
the longer name. The renderer then audits its own output for anything still
matching `__NAME__` and refuses to write a file carrying one. A placeholder
added to a template here, and not to the renderer, fails at the render rather
than at the first `nginx -t`.

## The files

| File | What it is |
|---|---|
| `keycloak/realm-template.json` | The realm import document: three clients and eight personas |
| `nginx/edge.conf` | The edge at offset +0, and the only routing table |
| `oauth2-proxy/oauth2-proxy.cfg` | The relying party behind `auth_request` |
| `compose/auth.compose.yaml` | The `edge`, `oauth2-proxy`, `keycloak`, `migrate` and `seed` services |
| `compose/product.example.yaml` | The `db`, `server` and `client` services a product defines itself |

## The three clients

| Client | What it is for |
|---|---|
| `__REPO__` | The confidential client oauth2-proxy runs as. It holds the tokens and owns the browser session |
| `__REPO__-admin` | The service-account client the application's control plane authenticates with, for the four provisioning operations of AU4 |
| `__REPO__-devtools` | A public direct-grant client, for local tooling that mints a persona's token without a browser |

The devtools client exists because a functional test wants a token and not a
login page. It is a local development client, and a rendered realm is never
deployed anywhere.

## What the realm file cannot say in itself

JSON carries no comments, so the reasoning behind four of its settings lives
here.

**No role mappers and no group mappers, anywhere.** AU2 keeps authorization
out of the token, and the RB rules put roles in the application. The mechanism
is two settings per client: `fullScopeAllowed` is false, and the `roles` scope
is absent from `defaultClientScopes`. Adding either back puts `realm_access`
into the ID token, and the application's access control then depends on
provider configuration. A realm shipping role mappers defeats the standard
silently, so this is not an omission to correct.

**The admin client is the one exception.** Its service account carries
`realm-management` roles, because Keycloak's admin API authorizes from them.
Those roles govern the provider's control plane and never reach the
application. That is why `__REPO__-admin` keeps the `roles` scope and the other
two clients do not.

**The subject identifier type is public.** AU3 requires it, because a pairwise
subject differs per client for one human. Two applications behind one provider
then cannot tell they are looking at the same person. Keycloak makes a subject
pairwise through a protocol mapper, so public is the absence of one. Every
client here declares `protocolMappers` as an empty list.

**The lifespans are AU5's numbers.** The token lives 300 seconds, the session
idles out after 28800, and it ends absolutely at 604800. `duplicateEmailsAllowed`
is false and `verifyEmail` is true, because AU3 keys provisioning on an address
that is unique and verified.

## The eight personas

Subject ids are fixed in the file. A test that logs in as a persona and asserts
on a subject cannot have that subject change per machine.

| Persona | Subject | What it exercises |
|---|---|---|
| `platform-admin` | `aa000001-…-000000000001` | A grant that is global rather than inside one tenant |
| `tenant-a-admin` | `aa000002-…-000000000002` | Administration inside one tenant |
| `tenant-b-admin` | `aa000003-…-000000000003` | The same, in a second tenant, so isolation has two sides |
| `two-tenant-member` | `aa000004-…-000000000004` | AU8: one session acts in one tenant, and switching is an act on the session |
| `single-tenant-member` | `aa000005-…-000000000005` | The ordinary case, where one grant is active without a choice |
| `no-application-access` | `aa000006-…-000000000006` | AU6: an authenticated subject the application does not know is refused and logged out |
| `deactivated-member` | `aa000007-…-000000000007` | A disabled identity, refused at the provider |
| `unverified-email-member` | `aa000008-…-000000000008` | An unverified address, refused at the login page and again at the proxy |

The realm holds identities and nothing else. Which tenants a persona belongs to
is application data, written by the `seed` one-shot against the product's own
tables.

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

## The cookie

`__Host-__REPO__-session`, with `HttpOnly`, `Secure`, `SameSite=Lax` and
`Path=/`. `cookie_expire` is 604800 seconds, which is AU5's absolute maximum
and the same number the application reports as the session's expiry.
`cookie_refresh` sits inside the 300-second token lifespan, so the forwarded
token is renewed behind an unchanged cookie.

**There is no `cookie_domain`.** Topology A is one origin, so the browser
scopes the cookie to the host that set it. Setting a domain widens the cookie
to every host under it. The `__Host-` prefix stops being available at all.

## The edge

`auth_request /oauth2/auth` guards every path that is not on the skip list.
`auth_request_set $token $upstream_http_authorization` reads the ID token
oauth2-proxy returns, and each guarded location forwards it upstream.

**An inbound `Authorization` header never reaches a backend.** Every location
that proxies sets the header explicitly. A guarded location sets it to the
token from the subrequest. Every other location sets it to the empty string.
The subrequest location clears it too, because nginx passes the client's
headers into the subrequest by default.

That repetition is load-bearing. nginx drops every inherited `proxy_set_header`
inside a location that declares one of its own. A block written once at server
level would therefore vanish from exactly the locations that matter.

The skip list carries only paths a standard defines as answerable before anyone
is known. A product's own public paths are not on it. They come from its
`deploy/public.json` and are rendered beside it, as the Rendering section
says.

| Path | Where it comes from |
|---|---|
| `/healthz`, `/readyz` | [`standards/030-service.md`](../standards/030-service.md) SC1 |
| `/config.json` | [`standards/090-web-client.md`](../standards/090-web-client.md) WC2 |
| `/.well-known/security.txt` | [`standards/085-security-baseline.md`](../standards/085-security-baseline.md) SB7 |
| `/api/client-errors` | [`standards/090-web-client.md`](../standards/090-web-client.md) WC5 |

WC5 fixes that report's shape and not its path. So the edge names
`/api/client-errors`. A product with a path of its own renders that line to
match.

`/logout` is the RP-initiated logout of AU5 in one hop. It ends the proxy
session and then sends the browser to the provider's end-session endpoint.
Ending only the first leaves the provider session alive, and the next sign-in
click signs the person straight back in.

The API is also published at offset +1, which is how a developer reaches it
directly with a token. That path skips the edge by design. It is safe because
form (a) makes the backend verify the token for itself. The signature, the
issuer, the audience and the expiry are all checked there.

## What the product supplies

The fragment defines five services and expects three more:

| Service | Who defines it |
|---|---|
| `edge`, `oauth2-proxy`, `keycloak`, `migrate`, `seed` | The fragment |
| `db`, `server`, `client` | The product, in its own `compose.yaml` |

The two one-shots run the product's own commands. `tools/migrate` applies the
identity tables, and `tools/seed-personas` writes the application-side user and
grant rows the realm's personas correspond to. Both are idempotent, both exit,
and `docker compose up` runs them in order before anything serves.

## Checking a change

Compose validates port numbers, so both commands run against a rendered tree
rather than against the templates.

```sh
docker compose -f deploy/compose/auth.compose.yaml \
               -f deploy/compose/product.example.yaml config

python3 -c "import json; json.load(open('deploy/keycloak/realm.json'))"

nginx -t -c /path/to/a/wrapper/that/includes/deploy/nginx/edge.conf
```
