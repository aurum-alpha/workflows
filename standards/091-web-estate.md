# The web estate: three surface classes, the front door, and the seams between them

## Why this exists

Every standard before this one governs a process, or a browser talking to one.
A product business also runs at least one surface that is neither. That is a
public site anyone can open, which authenticates nobody and changes weekly in
the hands of people who do not deploy services. Nothing written here applied
to it. So the decisions it forces were being made by whoever built it first.
Those are what identity it can hold, what host it lives on, where its copy
lives, and how it hands a visitor to the product.

Those decisions are entangled with two others that look unrelated until the
first incident. A product that gives customers their own hostnames has, in
effect, many product hosts. A business with staff tools has a third kind of
surface again. The three kinds differ on exactly the axes a standard exists to
pin. Those are who arrives, what identity is held, whether a process exists,
and how often it changes. A surface that is a little of two of them is where
the credentials of one leak into the exposure of the other.

**A marketing page that can set a session cookie is a product surface with
none of the product's controls**. A staff tool under the product's domain is
one cookie attribute away from receiving a customer's session.

It is one document, the estate, rather than a front-door standard alone,
because the front door's rules only make sense against the other two classes.
What it is not permitted to do is defined by what the product does. Where its
seams are is defined by what sits on the far side. Written alone it would be a
list of prohibitions with no argument.

One more thing is stated because it would otherwise be assumed. Coding agents
will do much of the maintaining of these surfaces, and every property below
that helps an agent helped a person first. **Agents are a beneficiary of these
rules and not their justification**.

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

The front door is the odd one out. It is not a *service* in the platform
contract's sense. It has no process, so the service contract, the workers
standard and the live checks of the security baseline do not reach it. It
therefore gets its own rules, WE3 and WE4. The product and internal surfaces
are governed by the standards already written. This document says which they
are and where they end.

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
apply, and why what follows is stated here instead.

**A front door has environments**: development, staging where the product has
one, and production. This is the rule's load-bearing clause. It has them for
the same reason a service does: a value on the page differs between them. A
booking link, a form endpoint, the origin the sign-up handoff points at: each
is environment-specific. A development deployment carrying the production
value has sent a test through the production funnel.

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

- **The build produces one artifact, identical in every environment**
  ([factor V](https://12factor.net/build-release-run); the
  [CI standard](010-ci.md), Principle 7, BUILD ONCE). The environment
  enters at the origin, not at the build. That is
  [factor III](https://12factor.net/config) honoured through the serving
  process's environment, as WC2 argues in full. An origin that cannot render
  a per-environment document forces the value into the build. One build per
  environment is the failure both factors name.
- **A host that can only serve files cannot host a front door**. That is the
  property, stated as WC2's property of the origin rather than as a verdict
  on any hosting arrangement. A static server in a container that writes the
  document at start from its environment satisfies it. A static host whose
  deployment step writes the document into the served directory from the
  environment satisfies it. A bare object store receiving the build output
  and nothing else does not. The register names which known arrangements
  are which.

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
a change someone can point to**. A content change lands as a pull request, and
the front door's gates run. A human reads a content diff, and a build produces
the directory WE3 serves. That is the whole of the flow, and it is the same
flow every other change in this organisation takes. It is stated because the
pressure on a front door runs the other way. That pressure is towards an
editor that publishes now, with no build and nothing to review.

That pressure is refused here with its reason. **Content that went live with
no build and no record is content nobody can reproduce, roll back or account
for**. And that is on the one surface whose every word is a public statement
by the business.

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

**A pricing page renders from a catalog it does not own**. Prices, plans and
what each includes are the product's, held in one place the billing standard
governs (tracked on [the capability
roster](000-platform.md#the-capability-roster)). The front door reads them as
it reads any declared source. They are pulled into the repository as data,
rendered by a component, and never typed into a content file. Two sources of a
price disagree in the week it matters, and the one on the public page is the
one a customer screenshots.

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

Those are properties of the surface, not of who maintains it. A repository
that builds alone can be reviewed, handed over and recovered alone when the
person who knew the missing piece has gone. That the *someone* in the test can
be an agent makes the test cheap enough to run on every change. That is the
entire extent of what agents contribute to this rule. It is not why the test
exists.

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
authenticated call to send it through.

A name or an email typed into the front door for sign-up is personal data on
the one surface with no controls for it. WE3 refuses it before this rule is
reached. The promotional code is admitted because it is not personal; its
validity is decided on the product.

**Lead capture is the front door's one admitted form**, admitted under
conditions rather than by exception. It posts to a processor the repository
declares, or to an intake endpoint the internal surface exposes. The internal
surface defends that endpoint as the baseline requires of every open route. It
never posts to the product, because a lead is not a customer. The front door
keeps nothing: it neither stores the submission nor reads it back. So a
visitor's data passes through the one surface that cannot protect it without
resting there.

Who is permitted to show, transact and override across these seams is stated
below.

### WE7. An automated actor on any surface is a workload identity

**A pipeline, a bot or an agent acting on a surface acts under an identity
issued to the workload**. That is OIDC federation from the pipeline to the
platform or the host, as [`032-secrets.md`](032-secrets.md) SE9 prefers. It is
never a long-lived key held in a secret store, and never a credential borrowed
from a person. On the internal surface it is a subject in its own right under
[`070-rbac.md`](070-rbac.md), holding its own grants. Its acts carry its own
name in the audit record ([`080-audit.md`](080-audit.md) AE2).

The reasons hold for every non-human actor and hold harder here, because the
surfaces are where the acts become visible. **A borrowed human session makes
the human the actor of record**. Every act is audited as theirs, every
permission exercised is theirs, and revoking the automation means revoking
them. **A long-lived key is a credential with no expiry in the place with the
most exposure**. The front door's deployment credential can change every
public word of the business. Federated, it exists for one pipeline run, bound
to one repository and one environment.

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
session cookie can reach in the admitted `Domain=` topology. It is one the
product's certificate arrangements answer for, and one a reader of the name
will class as product. That is a front door surface with a product host's
exposure, built and discarded at a cadence no product surface has. That is the
mix of classes WE1 exists to prevent, arriving through the door marked
*temporary*.

Under the apex a campaign page inherits exactly the posture it needs. That is
no cookie, no credential, a build and a record (WE4), and retirement by
deleting a directory.

## Commerce across the seams

Pricing, sign-up, trials and plan changes cut across all three surfaces, which
is why they need a boundary rather than a home. One principle decides every
row. **The front door displays and links; the product transacts; internal
tools override and observe; and one catalog is the shared truth**. What
follows is the estate's half of that principle. The catalog itself, the
subscription and its history, checkout and the provider adapter are the
billing standard's. So are what an entitlement is and how it is checked, all
tracked on [the capability roster](000-platform.md#the-capability-roster).

| Concept | Shown on | Transacted on | The crossing |
|---|---|---|---|
| **Plan catalog** | front door pricing page; product billing page; internal admin | nowhere; it is read | The front door renders from it as a declared source (WE4). A price is never typed into front-door content. |
| **Pricing page** | front door | nowhere; content plus a catalog render | Each plan's call to action is the sign-up handoff (WE6): a link to the product's entry with the plan and campaign source as query parameters. |
| **Sign-up** | the entry is a link on the front door | the product | The front door never renders a form collecting a name or an email for sign-up. That is what keeps it anonymous and store-less. |
| **Trial and plan state** | product; internal admin | product | Product → internal as 055 events (WE6). |
| **Upgrade, downgrade, cancellation** | product billing settings | product | Nothing crosses a seam. |
| **A change on a customer's behalf** | internal admin | internal tool calling the product | Internal → product over 050 with a 070 permission and an 080 event (WE6). Never through the product's interface on a borrowed customer session (WE7). |
| **Contact sales** | front door, the one form it is allowed | a declared intake endpoint or processor | Front door → internal (WE6). Sales provisions the tenant from the internal surface, which is 060 AU4's administrator-created path; the product is not involved until then. |
| **Promotional code** | the front door can carry one in the handoff | the product's checkout | A code is non-personal context, so the handoff can carry it; its validity is decided on the product. |

Two shapes this table refuses are reached for first. **A sign-up form on the
front door** is personal data on the surface with no controls for it (WE3,
WE6). **Prices typed into front-door content** are a second source of a fact
the catalog owns (WE4). The page renders the offer and does not define it.

## The artifacts

This standard adds no artifact of its own, deliberately. The one document it
requires a surface to serve is the web client standard's bootstrap document,
under [`contracts/web-client/`](../contracts/web-client/). A second schema for
it would be this repository's two-answers failure. The seams of WE6 are
contracts other standards already hold. What this standard pins that no
contract holds is the classes, the host convention, and the test of WE5. Each
is a property of an estate rather than a shape on a wire, and the ledger says
so.

## Decisions

- **The front door is its own repository and its own deployable**
  (2026-09-04). A directory in the product's repository, and a separate
  deployable cut from that repository, were both refused. The grounds each
  hold alone, and together over-determine it. Change cadence: a front door
  changes weekly in the hands of people who do not deploy services. A
  repository whose gates are the product's makes every copy change wait for
  a test suite it cannot affect. Blast radius: a front door that ships with
  the product can be broken by a release and can break one.

  Handover: a client's public site and a client's product part company more
  often than they stay together. A gate set that fits static content: a
  build, a link check, a content diff, and none of the live checks written
  for a process. And a repository small enough that one maintainer, human or
  agent, can hold all of it. That is WE5 in the only form that stays true as
  the product grows.
- **The host convention is a security boundary because of the cookie**
  (2026-09-04). The first draft placed hosts by convention and left the
  reason as tidiness. The reason that survives is the reach of a `Domain=`
  cookie in an admitted topology, which makes the registrable domain a blast
  radius. The host map was drawn from that fact, with host-only cookies on
  the product's side as the rule that makes it hold
  ([`092-tenant-hostnames.md`](092-tenant-hostnames.md) TH4).
- **A front door has environments, and WC2 applies unchanged** (2026-09-05).
  The temptation was to call a marketing site environment-less and let the
  build carry its links. A booking URL, a form endpoint and the sign-up
  origin each differ between development and production. Once a front door
  has environments, the web client standard's answer to *how does a built
  artifact learn its environment* is already written. A second answer would
  be the two-answers failure.
- **Build it as code, yes; whether to run the serving stack is a property,
  not a verdict** (2026-09-05). Authoring the front door as a repository was
  never in question. Whether to operate its origin began as a refusal, and
  ended as WE3's property once the environments ruling landed. Any
  arrangement whose origin renders a per-environment document is admitted.
  The register carries the arrangements; the standard carries the property.
- **The stack is open below the contract** (2026-09-06). The generator, the
  host and the content source are not pinned. The rules are stated in terms
  none of them own: a directory, an origin, a document, a diff. Pinning a
  tool would put the most perishable sentence in the most durable document.
- **A declared source lands in the repository before the build reads it**
  (2026-09-06). A build that fetches from the content system at build time
  was refused because it makes the build a function of when it ran. So the
  same commit produces different sites, and no record says which words
  shipped. The pull is a change, the change is a diff, and the diff is what
  a human reviews.
- **No personal data on the front door, with one named exception**
  (2026-09-07). A sign-up form is the shape every product reaches for and
  the one that ends the front door's anonymity. Lead capture is admitted
  because a business has to be contactable. It is admitted under conditions,
  and not as a licence for forms in general.
- **Tenant hostnames are their own document** (2026-09-07). They are product
  topology, and the rules they need are rules about authenticated surfaces
  that this document has no business stating. The estate places them; the
  [tenant hostnames standard](092-tenant-hostnames.md) governs them.
- **The front door displays and links; the product transacts**
  (2026-09-08). Pricing, sign-up and plan changes were candidates for this
  document in full, and would have made it a billing standard by accident.
  What stays is the estate's half: which surface is permitted to show,
  transact or override, and the seam each crossing uses. Everything that
  takes money or changes what a tenant is entitled to is the billing
  standard's, cited by its roster row rather than pre-empted.
- **Agents are a beneficiary of these properties, not their justification**
  (2026-09-08). This is stated as a decision because the opposite was
  argued. Every rule above that helps an agent is separation of concerns,
  minimal dependencies and a reproducible build. That is a repository that
  builds alone, content as a diff, a seam as a named contract. Each was good
  design before any agent existed, and each is checkable without reference
  to who will do the maintaining. Agents will do much of it, and WE5's test
  is cheap because of them, but no rule here rests on that.
