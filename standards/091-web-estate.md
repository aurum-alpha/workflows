# The web estate: three surface classes, the front door, and the seams between them

## Why this exists

A product business runs three kinds of web surface: a public site anyone can
open, the product customers authenticate into, and the tools staff use. They
differ on who arrives, what identity is held, whether a process
exists, and how often they change. A surface that is a little of two of them
is where the credentials of one leak into the exposure of the other. **A
marketing page that can set a session cookie is a product surface with none
of the product's controls**. A staff tool under the product's domain is one
cookie attribute away from receiving a customer's session. The front door's
rules only make sense against the other two classes, so this is one document,
the estate.

## The rules

### WE1. A surface belongs to one of three classes, and the class fixes its identity posture

A product business runs three kinds of web surface. They differ on the axes
that matter, and **a surface is in one class only**.

| Class | Who arrives | Identity posture | Has a process | Changes |
|---|---|---|---|---|
| **Front door** | Anyone, anonymous | None. No session, no credential, nothing to leak | No. A built directory, served by an origin | Often, and by people who do not deploy services |
| **Product** | Customers, on the default entry and on every tenant host | Tenant-scoped identity under [`060-auth.md`](060-auth.md), authorization under [`070-rbac.md`](070-rbac.md) | Yes, under [`030-service.md`](030-service.md) | On release |
| **Internal** | Staff, and automated actors as workload identities (WE7) | Workforce identity under 060, never a tenant's identity | Yes, under 030 | Continuously |

The identity posture is the axis that makes this a rule and not a taxonomy.
Each class holds exactly one kind of identity, and each kind is dangerous on
the other two surfaces:

- **A front door that holds any identity is a product surface without the
  product's controls**. The moment it sets a cookie or calls an
  authenticated API, it is inside the boundary. That boundary belongs to a
  surface with no rate limits, no audit, no readiness check and no release
  process. It needed none while it was anonymous.
- **A product surface that accepts workforce identity has given staff a
  customer's view of a customer's data**. Their acts are a customer's acts
  in the audit record. Staff act on a tenant through the internal surface
  and the seam WE6 names. There the actor is a staff subject, and the event
  says so under [`080-audit.md`](080-audit.md) AE2.
- **An internal surface that accepts tenant identity is reachable by a
  customer**, whatever authorization it runs.

The front door has no process, so the service contract and its live checks do
not reach it; WE3 and WE4 govern it instead.

### WE2. The host convention is the class boundary, and the class is decidable from the name

**Which class a host is in is decidable from the host name alone**. The apex
and `www` are the front door. The default entry (`app.`) and every tenant host
are the product. Internal tools live on a zone the product never sets a cookie
for. A host that is in no class is a host that does not exist, and the edge
answers it as one ([`092-tenant-hostnames.md`](092-tenant-hostnames.md) TH3).

| Zone | Hosts | Terminates at | Cookie |
|---|---|---|---|
| **Front door** | the apex; `www`, which redirects to it; campaign hosts under the apex (WE8) | a static origin, never the product | none, ever |
| **Product** | the default entry `app.`; tenant subdomains; customer domains pointed at the product | the product's edge | host-only, `Domain=` never set (092 TH4) |
| **Internal** | a zone of its own, never under the product's registrable domain | the internal edge, behind the workforce identity provider | the internal surface's own; never one the product set |

The reason this is a security boundary rather than tidiness is the cookie
column. A session cookie's reach is decided by the host that set it and the
attributes it carries. The [authentication standard](060-auth.md) AU7 admits a
topology whose cookie carries `Domain=` and therefore reaches every subdomain
of the registrable domain.

**Any host that shares the product's registrable domain is inside the reach of
a product session cookie in that topology**. So the front door setting no
cookie is not enough on its own. The internal surface has to sit where no
product cookie can arrive. That is a zone the product never sets a cookie for,
in practice a different registrable domain.

Decidability from the name is what makes the boundary operable. An edge that
has to look inside a request to know which class it is serving has already
served part of it. A reviewer who has to read a deployment manifest to know
whether a host is public or internal will not. The name carries the class so
that every check is made without consulting anything else. Those checks are
the edge's routing, the cookie posture, the certificate allowlist of 092 TH7,
and a reviewer's eye.

Under white-label, the customer's own marketing is the customer's, on the
customer's domain. The product's front door never reaches it. A customer
domain pointed at the product is a product host (092), not a front door.

### WE3. The front door is a built directory, not a service, and it has environments

**The front door is a directory of files produced by a build, served by an
origin**. It holds no session, no credential, and makes no call to an
authenticated API. There is no process of its own to be healthy, to log, to
drain or to be provenance-checked. That is why the service contract does not
apply.

**A front door has environments**: development, staging where the product has
one, and production. It has them for the same reason a service does: a value
on the page differs between them. A booking link, a form endpoint, the origin
the sign-up handoff points at: each is environment-specific. A development
deployment carrying the production value has sent a test through the
production funnel.

The [web client standard](090-web-client.md) WC2 already states how a browser
surface learns such values without compiling them in, and it applies here
unchanged. **The origin that serves the directory renders the bootstrap
document from its own environment**. It does so in the shape
[`contracts/web-client/runtime-config.schema.json`](../contracts/web-client/runtime-config.schema.json)
defines, at the path and with the caching WC2 pins. The front door's document
carries its surface-specific values under the member WC2 supplies for them,
declared per repository. It carries no API origin or login path, because under
this rule it has nothing to call and nobody to log in.

Two consequences, each following from something already written:

- **The build produces one artifact, identical in every environment**, and
  the environment enters at the origin, as [`090-web-client.md`](090-web-client.md)
  WC2 argues in full.
- **A host that can only serve files cannot host a front door**. That is
  WC2's property of the origin, stated as a property rather than as a
  verdict on any hosting arrangement. Which static hosts and generators
  satisfy it is [`solutions/091-web-estate.md`](../solutions/091-web-estate.md)'s
  to say.

What the directory is not permitted to contain follows from *no credential*:
nothing that would be a finding under [`032-secrets.md`](032-secrets.md) SE4
in a repository. The directory is served to every visitor and is more public
than any repository. A third-party service the front door talks to is one that
accepts an anonymous request or a key intended to be published.

### WE4. Content is data in the repository, and nothing is live without a build and a record

**Copy lives in content files that components render**. A heading, a paragraph
of positioning, a plan's description, a testimonial: each is data in the
repository, in a format a person reads as prose. So a change to a sentence is
a small diff a reviewer reads as a sentence and not as markup. Components
render content; they do not contain it.

**The site is rebuilt from the repository, and every change to what is live is
a change someone can point to**. A content change lands as a pull request, the
gates run, a human reads the diff, and a build produces the directory WE3
serves. The pressure on a front door runs the other way, towards
an editor that publishes now, with no build and nothing to review. **Content
that went live with no build and no record is content nobody can reproduce,
roll back or account for**. And that is on the one surface whose every word is
a public statement by the business.

**A content management system is admitted only as a declared source**. The
declaration is in the repository: which system, which content types, under
which credential name per 032 SE2. What the system supplies enters the
repository as content files before the build reads it. The pull that brings it
in is itself a change like any other. The build reads the repository and
nothing else. The rule is shaped this way rather than as *the build fetches
from the CMS* for two reasons.

**A build that fetches at build time does not reproduce**. The same commit
built an hour apart produces two sites, and neither the release nor the record
says which words shipped. Factor V's release is a build plus configuration,
and content fetched during the build is neither. And **a pull that lands in
the repository is a diff a human can read**, which is the only form of review
this rule accepts. What the system publishes on its own is content live
without a build, and is refused. That is a hosted preview served publicly, a
page rendered at request time, or a script fetching copy at load.

**A pricing page renders from the catalog [`075-billing.md`](075-billing.md)
BL1 governs**, pulled into the repository as a declared source and never typed
into a content file.

### WE5. Every surface is maintainable from its repository alone

This is separation of concerns and minimal dependencies, stated as a test
rather than as a value. A value cannot fail and a test can:

> Hand the repository to someone with no other access, human or agent, and
> ask for a copy change. If what results is a reviewable pull request that
> passes the repository's gates, the surface is maintainable from its
> repository. If it is not, the surface depends on something outside its
> repository, and **that dependency is the defect**.

The test is run against the repository as it is. That is a clean checkout, the
credentials `.env.example` names under [`032-secrets.md`](032-secrets.md) SE9,
and the gates runnable locally as the [CI standard](010-ci.md)'s second
principle requires. A surface that fails it fails for a dependency nobody
wrote down. That is a build that needs a credential nobody in the repository
can name, or content that lives somewhere the repository does not declare. It
is a gate that only runs in one person's environment, or a deployment that
needs a hand on a console.

A repository that builds alone can be reviewed, handed over and recovered
alone when the person who knew the missing piece has gone.

**The front door is its own repository and its own deployable**. A directory
in the product's repository makes every copy change wait for a test suite it
cannot affect. A front door changes weekly, in the hands of people who do not
deploy services. A front door that ships with the product can be broken by
a release and can break one. And a client's public site and a client's product
part company more often than they stay together.

### WE6. The seams are the existing contracts, named, and no other route crosses one

Three classes touch at four seams, and **each seam is a contract another
standard already states**. This rule names them and closes the set. A route
between surfaces that is not one of these four is a route that crossed a class
boundary without one, and it is refused.

| Seam | The crossing | The contract |
|---|---|---|
| **Front door → product** | The sign-up handoff | A link to the product's entry, carrying only non-personal context as query parameters: the plan chosen, the campaign source, a promotional code. Sign-up itself runs on the product, where the application creates the tenant, its first administrator and the identity ([`060-auth.md`](060-auth.md) AU4). |
| **Front door → internal** | Lead capture | A form posting to a declared external processor, or to a declared public intake endpoint that is rate limited ([`085-security-baseline.md`](085-security-baseline.md) SB5) and schema-validated (SB6), and that is not the product's API. What arrives is delivered to the internal surface; the front door stores nothing. |
| **Product → internal** | Tenant and account lifecycle | Events under [`055-messaging.md`](055-messaging.md): a tenant created, a trial started, a plan changed, each a CloudEvent produced through the outbox. |
| **Internal → product** | Operations on a customer's behalf | Calls over [`050-http.md`](050-http.md), authorized by a [`070-rbac.md`](070-rbac.md) permission held by the staff subject, and each one an [`080-audit.md`](080-audit.md) event naming the staff actor and the tenant target. Never a borrowed customer session. |

**The first two seams are the whole of what the front door is permitted to
do with a visitor's intent**. **Together they keep it anonymous**. The sign-up
handoff carries nothing personal because the front door has nowhere to put
anything personal. It has no session to bind it to, no store to keep it in, no
authenticated call to send it through. Lead capture is the one admitted form,
because a business has to be contactable, and the front door keeps nothing of
what passes through it.

Across these seams, **the front door displays and links; the product
transacts; internal tools override and observe; and one catalog is the shared
truth**. Everything that takes money or changes what a tenant is entitled to
is [`075-billing.md`](075-billing.md)'s.

### WE7. An automated actor on any surface is a workload identity

**A pipeline, a bot or an agent acting on a surface acts under an identity
issued to the workload**. That is OIDC federation from the pipeline to the
platform or the host, as [`032-secrets.md`](032-secrets.md) SE9 prefers. It is
never a long-lived key held in a secret store, and never a credential borrowed
from a person. On the internal surface it is a subject in its own right under
[`070-rbac.md`](070-rbac.md), holding its own grants. Its acts carry its own
name in the audit record ([`080-audit.md`](080-audit.md) AE2).

**A borrowed human session makes the human the actor of record**, so every act
is audited as theirs and revoking the automation means revoking them. **A
long-lived key is a credential with no expiry in the place with the most
exposure**. The front door's deployment credential can change every public
word of the business. Federated, it exists for one pipeline run, bound to one
repository and one environment.

And **on the product, automation acts through the internal seam** (WE6), never
as a customer. An automated actor holding a tenant's identity is a
customer-class actor with nobody accountable behind it, which is the posture
WE1 refuses.

### WE8. Campaign pages live in the front door's zone

A campaign page is a front door surface: anonymous, built, served by a static
origin. That is a launch, an event, an experiment, a page with a life measured
in weeks. **It lives as a path or a subdomain of the apex, never in the
product's zone**. Disposable is fine; the zone is not negotiable.

The reason is WE2's. A campaign host under the product's zone is one a product
session cookie can reach in the admitted `Domain=` topology. A reader of the
name will class it as product. Under the apex it inherits no cookie, no
credential, a build and a record (WE4), and retirement by deleting a
directory.

## The artifacts

This standard adds no artifact; the front door's runtime document is
[`090-web-client.md`](090-web-client.md) WC2's schema under
[`contracts/web-client/`](../contracts/web-client/).
