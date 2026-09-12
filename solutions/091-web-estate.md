# Acceptable solutions: the web estate

Register for [`standards/091-web-estate.md`](../standards/091-web-estate.md).

This register covers the front door, which is the surface 091 specifies in
full. The product and internal surfaces are served by processes under the
standards that already govern them, and their registers are those standards'.

## What adopting anything does and does not do for you

An origin, a generator, a content source and a form processor get chosen;
five of the eight rules are the repository's whatever is adopted.

| Rule | What an adopted thing supplies | What is yours regardless |
|---|---|---|
| WE1 | Nothing. Which class a surface is in is a decision about the surface; a static origin makes *no process* the default shape, not the rule. | No session, credential or authenticated call on the front door; the other two classes kept off it. |
| WE2 | Nothing. A host's zone is DNS and edge configuration the repository writes. | The host map; the internal zone where no product cookie reaches. |
| WE3 | **An origin that renders the bootstrap document per environment** supplies the load-bearing half; the static-host rows below differ on exactly this. | The document's contents, its `surface_settings` declaration, a build artifact identical across environments. |
| WE4 | **A generator with a content layer** makes *content is data* the default shape: content files in one place, components elsewhere, a build that reads the first through the second. A content system supplies an editing surface. | Declaring every source, the pull into the repository, the review of a content diff, the catalog read for the pricing page. |
| WE5 | Nothing, and an adopted thing is the commonest way to fail it: a build that needs a hosted account, a content source that needs a credential nobody in the repository can name. | The test, against a clean checkout. |
| WE6 | A form processor supplies the far end of one seam, lead capture. The other three seams are between processes and have no tool here. | Declaring the processor or intake endpoint; a handoff link carrying nothing personal. |
| WE7 | Every static host in the table below accepts OIDC federation from the common CI systems for its deployment credential, when checked. Verify it for yours before assuming a long-lived deploy token is the only route. | Configuring federation rather than a token. |
| WE8 | Nothing. | The campaign page under the apex. |

## The property that decides an origin

Every host in the first table is entered against WE3's property, and three
shapes satisfy it:

- **A process at the origin renders the document at start** from its
  environment. A static server in a container does this with a template and
  the environment. The image is built once with the directory inside it.
- **The deployment step writes the document into the served directory** from
  the deployment's environment, after the build and before the files are
  live. The build never touches the document, so the artifact is identical.
  The deployment is what differs per environment, which is
  [factor V](https://12factor.net/build-release-run)'s separation exactly.
- **An edge function at the origin serves the document's path** from the
  host's per-environment variables, in front of a directory it otherwise
  serves as files.

A host that can do none of these is refused by WE3, and the refusal is in the
last table with the rule.

## The default route

**Content in the repository, no content system, and whichever generator the
repository's maintainers already know.** That is the whole default. It is
argued from WE4 and WE5 rather than from any tool's merits.

At a few dozen pages with one or two editors, the repository is the editing
surface and WE5's test passes with nothing outside it. Each content system
below adds a source, a pull, a credential name and a second place for content,
in exchange for an editing surface.

What would change the default is one of three things. The first is a volume
of editors who do not write markup and whose changes are routine. For them a
pull request per change is friction rather than review. The second is a
requirement for structured content shared with another surface, where a
content system's schema earns its keep. The third is a localisation workflow
with translators who need a tool. Any of those moves a repository to a
declared source, and the register says which are known to satisfy WE4 in that
role.

The origin and the generator have no default here. WE3's property is met by
every host in the table that is not refused. The generators differ on things
091 has no opinion about: templating, build speed, the framework a team
already uses.

## The register

The per-environment mechanism of each static host is the fastest-moving fact
on this page. Confirm it against the host's documentation before letting a
row decide.

### Static origins and edges, against WE3

| Option | How it renders the per-environment document | Prebuilt deployment | Notes against 091 |
|---|---|---|---|
| **A static server in a container** (nginx and its equivalents) | A process at the origin: a template rendered from the environment at container start, served at the document's path with `Cache-Control: no-store`. | The image *is* the artifact: directory plus server, built once. | Satisfies WE3 in the shape that needs no host-specific feature. The container is an origin and the front door remains a directory; it is not a service under 030, and a repository choosing it states in its Conventions that the service contract's live checks do not apply. TLS terminates at the platform's edge (085 SB4). |
| **Cloudflare Pages** | An edge function bound to the document's path, reading the project's per-environment variables; or the deployment step writing the file into the directory before upload. | Yes: upload a built directory from the pipeline rather than letting the host build. | Production and preview environments carry separate variables when checked. **Use the prebuilt upload**: the host's own build-per-environment would produce one artifact per environment, which WE3 refuses. |
| **Netlify** | An edge or serverless function at the document's path reading deploy-context variables; or the deployment step writing the file. | Yes: deploy a built directory from the pipeline. | Deploy contexts carry separate variables when checked. Same caution as above: the host's context-specific build is the build-per-environment shape; deploy prebuilt. |
| **Vercel, static output** | An edge function or route at the document's path reading the deployment environment's variables; or the deployment step writing the file. | Yes: prebuilt deployments from the pipeline. | Production, preview and development environments carry separate variables when checked. Deploy prebuilt for the reason above. |
| **AWS S3 behind CloudFront, with a deployment step that writes the document** | The deployment step renders the document from the pipeline's environment and writes it to the bucket after the build output, per environment. `Cache-Control: no-store` is set on that one object, or by a response headers policy on its path. | Yes by construction: the pipeline uploads the build output. | Satisfies WE3 through the deployment step and not through the store. CloudFront supplies TLS on the front door's hostname and the response headers 085 SB3 requires; the bucket alone supplies neither. |

### Static-site generators, against WE4

Every row builds a directory from files in the repository, which is the
shape WE3 serves. They differ on whether *content is data* is the default
arrangement or one the repository has to impose.

| Option | Content layer | Output | Notes against 091 |
|---|---|---|---|
| **Astro** | Content collections with a schema per collection; Markdown and MDX. | Static directory by default; a server output mode exists and is not the front door's shape. | The typed content layer makes WE4's *components render content* the default: a collection is data, a component is a template, and a content file that fails its schema fails the build. |
| **Eleventy** | The data cascade: front matter, directory data files, global data; any of several template languages. | Static directory. | Content-as-data is the model; MDX is available through a plugin when checked. Small dependency surface, which is a WE5 property. |
| **Hugo** | A content directory of Markdown with front matter; taxonomies; data files. | Static directory. | A single binary with no package tree, which is the smallest WE5 surface in the table. No MDX: components in content are shortcodes, which is a different authoring model and not a defect. |
| **Vite, multi-page** | None built in. | Static directory of one HTML entry per page. | Satisfies WE3 and WE4 only with discipline the tool does not supply: content ends up in components unless the repository builds its own content layer. Entered because a repository already using Vite for a product may reach for it; it is the row with the most left to the repository. |
| **Next.js, static export** | None specific; Markdown and MDX through the ecosystem. | Static directory when configured for export; the build fails on use of a feature that needs a server, which is a WE3 property working in the repository's favour. | A large dependency surface for a front door, and a framework whose default output is a server — the export mode is the only shape entered here. |

### Content sources, against WE4

| Option | Role under WE4 | How it lands in the repository | Notes against 091 |
|---|---|---|---|
| **Markdown or MDX in the repository** | The content itself. | It is already there. | The default route above. WE5 passes with nothing to declare. |
| **Contentful** | A declared source. | A pull through its delivery API, committed as content files; a webhook on publish can open the pull. | A hosted editing surface with a content model defined in the system, so the schema the build validates against is the repository's own restatement of it. |
| **Sanity** | A declared source. | A pull through its query API, committed as content files; a webhook on publish can open the pull. | The content schema is code the repository holds, which narrows the gap between the system's model and the repository's declaration. |
| **Payload** | A declared source. | A pull through its API, committed as content files. | Self-hostable, with the content schema defined in code in a repository. Entered in the build-source role only: run as a server rendering pages at request time it would be a process serving content live without a build, which WE4 refuses. |
| **Notion, as a build source** | A declared source. | A pull through its API, committed as content files. | The schema of a database lives in the tool's interface and nowhere in code, so the pull validates what it fetched against a declaration the repository holds, and a property renamed in the tool is a build failure rather than a silent blank. Suited to copy that people already write there; not suited as the schema of record for anything. |

### Form and lead processors, against WE6

| Option | The seam it serves | Where its address lives | Notes against 091 |
|---|---|---|---|
| **A booking tool** (a hosted scheduling page, linked or embedded) | Lead capture, where the lead is a meeting. | `surface_settings` in the bootstrap document, per environment, so development never books a real slot. | The front door links to it or embeds its widget; the submission is the tool's and the front door stores nothing. An embedded widget is a third-party script on the page, which the repository accepts knowingly and states in its Conventions. |
| **A form service** (a hosted endpoint the form posts to) | Lead capture, where the lead is a message. | `surface_settings`, per environment. | The declared external processor of WE6. Spam control and delivery are the service's; the front door keeps no copy. Whose personal-data inventory under 082 the submissions belong to is the receiving surface's question, and the declaration names the receiver so that it can be answered. |
| **The internal surface's public intake endpoint** | Lead capture, delivered into the internal surface's own systems. | `surface_settings`, per environment. | The declared public intake endpoint of WE6: unauthenticated, rate limited under 085 SB5, schema-validated under SB6, and not the product's API. The endpoint is a route on an internal-surface process and is governed as one; the front door only posts to it. |

## Routes 091 refuses, and the rule that refuses them

| Route | Refused by |
|---|---|
| A bare object store as the whole serving origin — the build output copied in and nothing written at deployment | **WE3**: no per-environment document, so the environment enters the build. Also **090 WC2** and 085 SB4. |
| A static host's own per-environment build, producing a different artifact for preview and production | **WE3**, for the same reason: the environment entered at the build. Every host in the table accepts a prebuilt directory, and that is the route entered. |
| An API origin, a login path or a session on the front door | **WE3**. A front door that has any of them is a product surface without the product's controls (WE1). |
| Content fetched by the page at load, or by the build at build time, from a content system | **WE4**: the pull lands in the repository; a fetch at load or at build does not. |
| A content system's own hosted preview or live rendering serving the public | **WE4**. Content live with no build and no record. |
| Prices typed into content files | **WE4**, the catalog clause: the page renders the offer and does not define it. |
| A sign-up form, or any form collecting personal data for the product, on the front door | **WE3** and **WE6**. Lead capture is the one admitted form, and it posts to a declared processor or intake endpoint, never to the product. |
| A long-lived deploy token in the pipeline where the host accepts federation | **WE7**, with **032 SE9**. |
| A campaign page under the product's zone | **WE8**. |

## Choosing, in order

1. **Can the origin render the document per environment, without the build
   knowing the environment?** If not, stop; WE3 refuses it. If yes, note
   which of the three shapes it uses. The pipeline has to implement that
   shape and not another.
2. **Does the host build, or accept a prebuilt directory?** Only the second
   keeps the artifact identical. Every host in the table can; check that the
   pipeline uses it.
3. **Does the generator keep content out of components by default?** A
   content layer decides that. With one, WE4 is the shape of the repository.
   Without one, WE4 is a discipline the review has to hold.
4. **Is there anyone to run a content system for?** If not, the default
   route. If so, which row's pull the repository can declare and land as a
   change.
5. **Where does the one form post, and is the address in
   `surface_settings`**? A form endpoint compiled into the page is the WE3
   failure in a small place.
6. **Does a clean checkout build and pass its gates with nothing else?**
   WE5's test, run once before the first deployment and cheaply thereafter.
