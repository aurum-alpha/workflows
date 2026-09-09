# Acceptable solutions: billing

The acceptable solutions register for
[`075-billing.md`](../standards/075-billing.md). It is not a standard and
states no rule — read
[the charter](../README.md#acceptable-solutions-the-register-of-what-satisfies-a-standard)
for what this class of document may and may not do. Every requirement below is
075's, cited by rule id; everything here is a claim that some route satisfies
one, and the date that claim was last checked.

Absence from this page is not refusal. An option nobody has entered is an
option nobody has surveyed, and a repository may take it by demonstrating
compliance against 075's rules — then enter it here so the next one need not.

## What adopting anything does and does not do for you

The most expensive mistake available here is believing that choosing a billing
provider implements the standard. A provider takes the money, and 075 is
mostly about what the product does with the fact that it did. **Four of ten
rules get nothing from a provider at all, and the other six get only the far
side of a call the repository still has to make**, because the catalog, the
ledger, the kinds and the check are what 075 invented rather than what it
borrowed.

| Rule | What an adopted thing supplies | What is yours regardless |
|---|---|---|
| BL1 | An API that creates products and prices, and archives them, so that `catalog.provision` can author the provider from the file. **Not every provider offers this**; the table says which did at the checked date, and a provider without it cannot satisfy BL1 by any route. | The catalog file, its schema validation in CI, the provisioning job and the id mapping it writes back, and never typing a price anywhere else. |
| BL2 | Nothing. Every provider holds its own subscription object with its own status vocabulary, and 075 says plainly that the product's projection and ledger are the entitlement truth. | All of it: the projection, the append-only ledger with recorded and effective times, the closed sets, the one pending change. |
| BL3 | Nothing. Four kinds distinguished by what the code does with the value is this platform's model; a provider's *features* or *entitlements* object, where one exists, is a display list with no check behind it. | All of it, including refusing anything per user. |
| BL4 | Nothing on the request path, by rule. Some providers offer an entitlements lookup API; using it per request is the shape BL4 refuses. | The pure function, the operations, the status policy, the order of checks, the `entitlement-required` problem, the cache with `valid_until`, the `/me` block. |
| BL5 | The adapter's far side: hosted checkout or tokenised fields, a customer portal, invoices, plan changes with proration and `cancel_at_period_end`, promotion codes. The provider's browser-side key is public by its design and reaches the page through the runtime configuration document (090 WC2). | Writing the adapter against 075's interface, selecting it from configuration (030 SC3), keeping the SDK out of domain code, and the credential out of the server image. |
| BL6 | Signed webhooks for every event 075's `verify` maps, with an event id and redelivery. The **signing scheme** is the provider's own at every row below; none documented Standard Webhooks signing at the checked date, so `verify` implements the provider's scheme inside the adapter. A read API the reconciliation job can page. | The AM8 endpoint, the consumer that maps events to ledger rows, and `billing.reconcile` with its finding-not-write discipline. |
| BL7 | Proration on upgrade and scheduled changes at period end, so the policies are one adapter call each. | The policies themselves, the over-quota rule, and keeping every change in the product rather than the dashboard. |
| BL8 | A trial period on the provider's subscription, and a webhook when it converts or ends. | The `trialing` status, `trial_end`, `trial.expire`, the notifications, and the declared free-tier-or-trial policy. |
| BL9 | An idempotent customer-creation call, so the boundary crossing can be retried on the tenant's id. | The one transaction, and its order. |
| BL10 | Nothing. | The audit event per ledger row, the inventory entries, the retention treatment. |

## The column that decides most

**Merchant of record or not.** A merchant-of-record provider is the legal
seller: it calculates, collects and remits sales tax and VAT in every
jurisdiction it sells into, carries the liability, and issues the invoice in
its own name. A payment-processor provider does none of that; the business
is the seller, tax is the business's obligation — some processors compute it,
none carry it — and the invoice is the business's.

That is a property of who the business is and where it sells, not of any
repository, so this register cannot decide it and names no default. What it
can say is that the two shapes satisfy 075 identically: BL5's adapter hides
the difference, BL6's webhooks arrive the same way, and the catalog, ledger
and check are the product's under either. The choice is made once per
business, before the first repository picks a row.

**Hosted against self-hosted** is the other genuinely open axis, and the
register takes no side. A self-hosted option keeps subscription data inside
the network and puts an operational burden on the team; a hosted one carries
the burden and holds the data. Both appear below.

## The register

Checked **2026-09-08** against each provider's own documentation. Webhook
schemes and catalog API coverage are the fastest-moving facts on this page:
confirm both against the provider's current reference before letting a row
decide.

| Option | Merchant of record | Payment capture (BL5) | Catalog by API (BL1) | Webhooks (BL6) | Metered usage (BL3 allowances) | Notes against 075 |
|---|---|---|---|---|---|---|
| **Stripe** | No. Tax computation is offered; liability stays with the business. | Hosted checkout and tokenised fields. | Yes: products and prices created and archived by API; a price is immutable once created, which is BL1's model exactly. | Own scheme, HMAC over timestamp and raw body, with event ids and redelivery. | Yes, through metered prices and meter events. | Scheduled plan changes and `cancel_at_period_end` map to BL7 one call each. |
| **Paddle** | Yes. | Hosted and overlay checkout. | Yes: products and prices by API. | Own scheme, HMAC over timestamp and raw body. | Verify: usage-based pricing existed at the checked date; confirm the event shape your allowance metric needs. | The merchant-of-record shape with a full catalog API, which is the combination the other MoR row lacked at the checked date. |
| **Lemon Squeezy** | Yes. | Hosted and overlay checkout. | **Verify.** At the checked date the API read products and variants and did not create them, so `catalog.provision` could not author the provider; the job can still reconcile against it. A row that cannot satisfy BL1 by any route is not a BL1 route. | Own scheme, HMAC over the raw body. | Yes, through usage records. | Acquired by the first row's vendor before the checked date; re-check that the API and roadmap named here are still this product's. |
| **Chargebee** | No. | Hosted pages and tokenised fields, over a payment gateway it sits in front of. | Yes: plans, items and prices by API. | Verify: at the checked date the documented endpoint authentication was a credential on the endpoint rather than a signature over the body. AM8 verifies a signature over the raw body, so confirm a body-signature scheme is offered before adopting. | Yes, through usage records and metered items. | A subscription-management layer rather than a processor; the gateway beneath it is a second vendor the adapter wraps, and BL5 says one adapter, not one vendor. |
| **Recurly** | No. | Hosted pages and tokenised fields, over a gateway. | Yes: plans and add-ons by API. | Verify: the same endpoint-credential question as the row above at the checked date. | Yes, through usage-based add-ons. | As above: a management layer over a gateway. |
| **Orb** | No. | None of its own: invoicing over a processor the adapter also wraps. | Yes: plans and prices by API. | Own scheme, HMAC over the raw body. | **Its reason to exist**: event ingestion and metering as the primary model. | Fits a product whose allowances are billed by consumption rather than capped. A product with no metered feature has no allowances (BL3) and no reason to reach for it. |
| **Lago** | No. | None of its own: invoicing over a processor the adapter also wraps. | Yes: plans and billable metrics by API. | Own scheme, signature header over the body. | **Its reason to exist**, as the row above. | Open source and self-hostable, which keeps subscription data inside the network at the cost of running it. |

"Verify" in a column means the claim was not confirmed for that option at the
checked date, not that it is absent — check before letting it decide.

## Routes 075 refuses, and the rule that refuses them

These are not omissions from the table; they are refused, and the refusal is a
rule in the standard rather than a preference on this page.

| Route | Refused by |
|---|---|
| Card fields on the product's own page posting to the product's own server | **BL5**: hosted checkout or tokenised fields only, and card data never touches our servers. |
| The catalog authored in the provider's dashboard, with the product reading it back | **BL1**: the catalog is a file in the repository and the provider is provisioned from it. A price that exists only in a console is a price no pull request reviewed. |
| A plan changed in the provider's dashboard | **BL7**, and **BL6** turns it into a finding. |
| The provider's entitlements or features API consulted on the request path | **BL4**: the ledger is the entitlement truth; the provider is never on the request path. |
| An entitlement kept as a toggle in a flag vendor's dashboard | **BL3** and **BL4**; 038 no longer has a kind for it to be. |
| The provider's SDK imported and called from domain code | **BL5**: a vendor SDK is only ever behind the adapter. |
| A management layer's webhook accepted on an endpoint credential alone, with no signature over the body | **BL6** via 055 AM8: verified over the raw body, then recorded, then processed. |
| The reconciliation job writing ledger rows to make the two sides agree | **BL6**: a disagreement is a finding, never a silent write, because which side is wrong is a judgment. |

## Choosing, in order

1. **Merchant of record, or not?** The business answers this once; it is not
   a repository's question and not a technical one. Rows that fail the
   business's answer leave the table.
2. **Can `catalog.provision` author it?** BL1 needs products and prices
   created and archived by API. A row that cannot is out, whatever else it
   offers.
3. **Does it sign webhooks over the raw body?** BL6 needs AM8's first step to
   be possible. An endpoint credential is not a signature.
4. **Hosted checkout or tokenised fields for every payment method the
   product sells with?** BL5.
5. **Does the product have allowances billed by consumption?** Only then does
   metering decide anything; a capped allowance is compared against the
   domain's own record and needs nothing from the provider.
6. **Where does subscription data live?** Self-hosted keeps it inside the
   network; hosted does not.

Price and contract terms are not on this list, and not on this page, per the
charter's third rule for this class.

## Re-checking this register

Every claim above carries the checked date at the head of the register. The
horizon is the charter's 180 days; the next re-check is due **2027-03-07**. A
re-check confirms, for each row: that the provider is still maintained and
still named what it is named, that its merchant-of-record status is unchanged,
that its catalog API still creates and archives, that its webhook scheme is
still the one stated, and that no new option has become obvious enough that
its absence is now misleading. Rows that fail are corrected or struck, and the
date moves.
