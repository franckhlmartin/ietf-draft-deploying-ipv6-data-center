%%%
title = "Deploying IPv6 in Data Centers"
abbrev = "deploying-ipv6-data-center"
ipr = "trust200902"
area = "ops"
workgroup = "IPv6 Operations"
keyword = ["IPv6", "data center", "SRE", "software", "operations", "deployment"]

date = 2026-07-07

[seriesInfo]
name = "Internet-Draft"
value = "draft-martin-deploying-ipv6-data-center-01"
status = "informational"

[[author]]
initials = "F."
surname = "Martin"
fullname = "Franck Martin"
organization = "Peachymango.org"
  [author.address]
  email = "franck@peachymango.org"
%%%

.# Abstract

Data center operators are moving toward IPv6-only operation to simplify
addressing, restore end-to-end connectivity, and meet operator and
government timelines. Much published IPv6 guidance targets network engineers;
this document instead addresses **Site Reliability Engineers (SREs)** and
**Software Engineers (SWEs)** who deploy, operate, and debug services in
**operator-owned data centers**. It is organized in two parts after IPv6 fundamentals: a
**migration program** (transition strategy and observability) and a
**technical stack** (hardware, provisioning, transport, applications, and
diagnostics). It documents common software and infrastructure gaps and offers
practical deployment patterns aligned with the IPv6 Operations (v6ops) working
group charter.

.# About This Document

This note is to be removed before publishing as an RFC.

The latest revision of this draft can be found at
https://github.com/franckhlmartin/ietf-draft-deploying-ipv6-data-center/.
Status information for this document may be found at
https://datatracker.ietf.org/doc/draft-martin-deploying-ipv6-data-center/.

Discussion of this document takes place on the v6ops Working Group
mailing list (mailto:v6ops@ietf.org), which is archived at
https://mailarchive.ietf.org/arch/browse/v6ops/. Subscribe at
https://www.ietf.org/mailman/listinfo/v6ops/.

Source for this draft and an issue tracker can be found at
https://github.com/franckhlmartin/ietf-draft-deploying-ipv6-data-center.

{mainmatter}

# Introduction

## Audience and Purpose

This document is written for **Site Reliability Engineers (SREs) and Software
Engineers (SWEs)** who run services in data
centers --- not primarily for network engineers designing routing policy.
Network teams still own prefixes, routing, and firewalls, but IPv6
deployment succeeds or fails in application code, configuration management,
monitoring pipelines, and the long tail of enterprise software that assumes
IPv4.

**Scope:** The primary audience runs services on infrastructure the organization
**owns or directly controls** --- operator-managed networks, prefixes, routing,
firewalls, and bare-metal or virtualized hosts in **physical or private data
centers**. This document does **not** prescribe how to deploy IPv6 **natively
inside third-party Infrastructure-as-a-Service (IaaS)** platforms (public cloud
VPCs, provider-managed Kubernetes, and similar). Each cloud provider imposes its
own addressing models, quotas, APIs, and processes; the deployer is **constrained**
by those platform choices in ways this draft cannot generalize. Operators with
hybrid estates **SHOULD** still understand cloud IPv6 gaps and connectivity
limits (see (#hybrid-cloud)) because those constraints often determine whether
an on-premise IPv6-only program can succeed.

## Related Guides

This document focuses on data center SRE and software engineering practice.
Operators and developers may also find these **informative guides** useful
alongside this draft:

* [@?RFC7381] --- enterprise IPv6 deployment framework (v6ops)
* [@?RFC4038] --- application aspects of IPv6 transition
* [@?ARCEP-IPV6-GUIDE] --- enterprise IPv6 rollout guidance from ARCEP (France)
* [@?ARIN-APPS-V6] --- application and software developer guidance from ARIN

They overlap partially with sections here (applications, addressing, operations)
but cover broader enterprise and regional context.

## Document Structure

This document uses a **dual-track structure** after (#ipv6-fundamentals): **Part I**
defines migration policy and measurement; **Part II** implements the stack from
management hardware upward. Fundamentals establish shared vocabulary for SREs
and software engineers; both parts are required for a complete IPv6-only data
center. Overlapping themes (for example internal vs external scope in
(#internal-external) and (#provision-not-transform)) appear where each audience
needs them; sections cross-link rather than repeat editorially.

**Part I --- Running the migration:** (#transition) covers operating model and
scope (greenfield provisioning vs brownfield conversion, IPv6-only jump hosts).
(#observability) defines inventory schema, dashboards, and success metrics ---
fix what you measure before bulk technical change.

**Part II --- Building the IPv6 data center** follows a bottom-up order: (#oob-management)
(hardware and management plane), (#internet-addressing) and (#dns-registration)
(provisioning), (#hybrid-cloud) (on-premise plus public cloud connectivity),
(#icmpv6-pmtud) (transport health), then application work ---
(#application-readiness), (#name-resolution), (#client-load-balancing) --- and
(#network-diagnostics) for production troubleshooting.

**Reading paths by role:**

* *Program lead / engineering manager:* Part I first, then Part II as overview.
* *Network / DC infrastructure engineer:* (#ipv6-fundamentals), then Part II
  sections on OOB through (#hybrid-cloud) and ICMPv6/PMTUD.
* *Application / SRE engineer:* (#ipv6-fundamentals), Part I (#observability),
  then Part II application and diagnostics sections.
* *Full migration owner:* linear --- fundamentals, Part I, Part II, then
  Security Considerations.

## Requirements Language

The key words "**MUST**", "**MUST NOT**", "**REQUIRED**", "**SHALL**",
"**SHALL NOT**", "**SHOULD**", "**SHOULD NOT**", "**RECOMMENDED**",
"**NOT RECOMMENDED**", "**MAY**", and "**OPTIONAL**" in this document are to
be interpreted as described in BCP 14 [@!RFC2119] [@!RFC8174] when, and only
when, they appear in all capitals, as shown here.

# IPv6 Fundamentals for Software Engineers {#ipv6-fundamentals}

Software engineers who have worked only in IPv4 environments often discover
that IPv6 is not "IPv4 with longer addresses." The differences below affect
code, configuration, monitoring, and troubleshooting daily.

## Address Size and Header Format

IPv4 addresses are **32 bits**; IPv6 addresses are **128 bits**
[@!RFC8200]. The IPv4 header has a **variable length** because options are
carried in the main header. The IPv6 header has a **fixed 40-byte length**,
which simplifies fast-path processing on routers and hosts. Additional IPv6
options live in **extension headers** chained after the main header; routers
**do not need to process** most extension headers for forwarding
[@!RFC8200].

## Checksums, Jumbo Frames, and Fragmentation

IPv6 removed the header checksum present in IPv4; integrity is assumed to be
covered by upper-layer protocols (for example, TCP, UDP, and SCTP) and link
layers where applicable [@!RFC8200]. Operators can use **jumbo frames** on
supported paths to reduce per-packet overhead and acknowledgment rates on
high-throughput links. Jumbo frames are an operational choice on the LAN and
require end-to-end support; they are not an IPv6 requirement but are often
easier to reason about once NAT middleboxes are removed.

IPv4 allowed routers to fragment packets in transit. IPv6 **fragments only at
endpoints** [@!RFC8200]. If a packet exceeds the path MTU, the source discovers
the limit through Path MTU Discovery (see (#icmpv6-pmtud)) rather than relying
on router fragmentation. Application teams that tune MSS or disable PMTUD on
IPv4 must not copy those habits blindly to IPv6.

## ICMPv6 and Neighbor Discovery

IPv4 Address Resolution Protocol (ARP) is replaced in IPv6 by **Neighbor
Discovery (ND)** carried in **ICMPv6** [@!RFC4861] [@!RFC4443]. ND resolves
addresses on the local link, discovers routers, and performs other essential
functions. **ICMPv6 therefore MUST NOT be blocked wholesale** on IPv6 paths
the way some IPv4 deployments block all ICMP. Blocking ICMPv6 breaks ND and
PMTUD and produces failures that look like application bugs.  Guidance exists
to identify essential ICMPv6 traffic that should not be blocked [@!RFC4890].

## End-to-End Connectivity

IPv4 data centers often rely on Network Address Translation (NAT), carrier-grade
NAT (CGNAT), and overlapping private address space [@!RFC1918]. IPv6 restores
the **end-to-end principle**: globally unique addresses (with deliberate
exceptions noted below) can be routed on the Internet without translation.
Routing replaces NAT for many multi-tenant container scenarios, which simplifies
traffic inspection but requires disciplined prefix planning (see
(#internet-addressing)).

## Address Types and Terminology {#address-types}

Careless use of the word "IPv6" causes outages. This document uses the
following terms:

**Link-local address**: An address in `fe80::/10` used only on a single link
[@!RFC4291]. Link-local addresses are **not** routed on the Internet. On
Linux, connecting to a link-local destination requires a **zone identifier**
(for example, `fe80::1%eth0`) because the same link-local prefix exists on
every interface.

**Unique Local Address (ULA)**: An address in `fc00::/7` intended for local
use and **not** globally routed [@!RFC4193]. ULAs resemble IPv4 private space
in purpose but are uncommon in many data center designs that use provider-
aggregated global unicast space internally. Like IPv4 private address space,
ULAs can create **renumbering work** when companies merge or networks are
combined --- a data center network is never final.

**Global Unicast Address (GUA)**: A globally routable IPv6 address assigned
from an organization's allocation of IPv6 addresses.

Unlike IPv4, there is **no RFC 1918 equivalent that dominates data center
design**. With rare exceptions (link-local, ULA, and special-purpose ranges
in [@!RFC6890]), **IPv6 unicast addresses are designed to be globally
unique and routable**. Security boundaries are enforced by routing policy and
firewall rules, not by assuming addresses are inherently non-routable.  We
use two additional terms to distinguish addresses based on thes policies:

**Internal global unicast address**: A globally routable IPv6 address used
**inside** the data center.  These addresses are reachable according to
routing and security policy, not because they are "private."

**External global unicast address**: A globally routable address presented to
clients on the Internet, often via load balancers or anycast.

Unlike IPv4, nodes typically have multiple IPv6 addresses assigned to each
of their interfaces.  The link-local addresses are necessary to participate
in Neighbor Discovery and so serve a vital purpose even though they are not
globally routable.  Additionally, because so many IPv6 addresses are
available, some machines may use multiple global addresses simultaneously
for purposes such as privacy or temporary use.

## Address Representation {#address-representation}

IPv6 addresses have several equivalent textual forms [@!RFC4291]:

* Full form: `2001:db8:0:0:0:0:0:1`
* Compressed zeros: `2001:db8::1`
* Loopback: `::1` (compare IPv4 `127.0.0.1`)
* Unspecified: `::`
* IPv4-mapped IPv6: `::ffff:192.0.2.1`

In **dual-stack** environments, IPv4 addresses also appear in multiple forms
in code and configuration:

* Dotted decimal: `192.0.2.1`
* Integer (historical APIs): `3232235521`
* Hex packed in configs: `0xC0000201`
* Mapped in IPv6 APIs: `::ffff:192.0.2.1`

In software, addresses **MUST** be stored in a **binary field or structure
sized for 128 bits** (for example, `in6_addr`, `sockaddr_storage`, or an
equivalent language type), so the same field can hold IPv4 or IPv6. **Do not
store addresses as strings** in databases, logs-as-data, caches, or message
payloads. Provide helper functions to convert between the binary form and a
human-readable representation for display and configuration I/O, and use those
helpers at boundaries --- **never parse or compare address strings ad hoc** in
application logic.

Applications **SHOULD** treat names, not literal addresses, as the stable
interface (see (#naming-services)). To turn a name into addresses, use the
APIs described in (#name-resolution) --- not legacy one-address helpers and
not string parsing.

## Prefix Length and the /64 Convention

On most LANs and data center segments, the **network/host split is at the
64th bit** --- a `/64` prefix on the wire [@!RFC4291]. Roughly speaking, a
`/64` is the IPv6 analogue of an IPv4 `/24` in terms of "one subnet per
broadcast domain," though the address space is vastly larger. A good data
center pattern assigns a **`/56` per host** so each container can receive its
own **`/64`** (see (#prefix-allocation)).

## Link-Local Gateways

A good practice is to place the default gateway at **`fe80::1`** on each
link. That choice avoids consuming a global address for the router and matches
common vendor examples. Servers **MUST** specify the outgoing interface when
using link-local next hops (for example, `ip -6 route add default via fe80::1
dev eth0`). The router platform **MUST** actually configure `fe80::1` on the
expected interface.

## Naming Services {#naming-services}

`::1` is `localhost`; `127.0.0.1` is `localhost`. **Do not embed IP addresses
in application code** when a name will do. Use hostnames and service discovery;
resolve names at connection time.

DNS (or an equivalent naming and service registry) becomes **essential** in
IPv6 because humans cannot memorize 128-bit addresses. Operational maturity
includes forward and reverse DNS for infrastructure, health checks keyed on
names, and monitoring that labels series by hostname rather than by address
literals.

# Part I: Running the Migration

# Transition Strategies {#transition}

## Easier to Provision Than to Transform {#provision-not-transform}

**It is easier to provision IPv6 correctly than to transform a running service.**
Enabling dual-stack or IPv6-only on a server, container, or service that was
deployed IPv4-only means changing addresses, ACLs, DNS, health checks, and
often application configuration --- then **restarting in place** and hoping
nothing was missed. Provisioning time already runs those checks, supports
canary or phased ramp-up, and catches failures before the service takes
production traffic.

Teams **SHOULD** treat every **new service**, **new software version**, and
**rewrite of an existing application** as an opportunity to ship **IPv6-only on
internal interfaces** from the start (see (#internal-external)), with **dual-stack
only where external reachability requires it**, rather than cloning an IPv4-only
template and scheduling conversion later. Brownfield conversion remains necessary
for legacy estates, but the default for greenfield work **SHOULD NOT** be
"IPv4 now, IPv6 someday."

## IPv4-Only Exceptions and Remediation Plans {#ipv4-only-exceptions}

The business will sometimes **require an IPv4-only product, service, or
technology** --- a vendor constraint, acquisition, regulated workload, or
time-to-market trade-off. Business goals matter, but **IPv4-only dependency
SHOULD NOT be discovered only after full production adoption**, when rollback is
expensive and the migration program has already assumed dual-stack or IPv6-only
readiness.

**Default to hard failure on missing IPv6 early** in inventory, CI, dependency
gates, and synthetic checks (see (#observability) and (#application-readiness))
so non-compliant software surfaces before it reaches tier-1 paths. Where IPv4-only
is genuinely required, use a **formal exception process** --- the same discipline
security teams apply to policy waivers:

* **Record the business reason** for IPv4-only adoption and who approved it.
* **Require a remediation plan** --- path to dual-stack, IPv6 support, or
  replacement --- with **milestones and a target date**.
* **Track progress** in the same service catalog and dashboards used for migration
  metrics; exceptions **SHOULD** expire or be renewed on review, not roll forever.
* **Flag dependents** so downstream teams know they are building on a known
  exception.

An approved exception **MAY** permit production use of IPv4-only software for a
bounded period; it **MUST NOT** be an informal verbal waiver. Review open
exceptions in change advisory or migration governance the same way security
reviews open risk acceptances --- stale plans become blockers again when dates
slip without an updated timeline.

## IPv6-Only Jump Hosts

Moving to IPv6 is not only a routing change --- it requires a **cultural shift**
for SREs and SWEs who have spent years assuming IPv4 literals, RFC 1918 mental
models, and IPv4-first tooling. **Make that shift visible before emergencies:**
IPv6-only jump hosts, IPv6-first runbooks, and labeled lab networks teach the
new defaults while change windows are calm. Engineers under incident pressure
**do not have time to learn IPv6 idioms**; if the first time they need `dig -x`
on an `ip6.arpa` name or SSH over a global v6 management address is during a
sev-1, the organization has already failed the migration program.

A practical staged transition puts **administrative jump hosts on IPv6-only**
access while leaving application tiers dual-stack temporarily. Engineers run
configuration management, monitoring CLI tools, and break-glass SSH from those
hosts, forcing administrative tooling onto IPv6. Maintain at least one
**dual-stack backup jump host** during migration and **audit who connects and
which commands run** until parity is proven.

Temporarily **reducing IPv4 SSH session timeouts** on jump hosts can accelerate
detection of accidental IPv4 dependency without blocking emergency access.

Apply the same staged exposure to **corporate wireless**, not only SSH bastions.
Provide **dual-stack Wi-Fi** for everyday employee devices during migration, and
at least one **IPv6-only employee Wi-Fi** SSID so laptops, phones, VPN clients,
and captive-portal flows are exercised on AAAA-only paths before production
depends on them. Label SSIDs explicitly (for example, `corp-dualstack` and
`corp-v6-only`) so engineers know which network they joined.

Some operators **MAY** additionally offer **IPv6-only guest Wi-Fi** --- for
example in lab, conference, or vendor demo areas --- so external teams can
demonstrate that hardware and software work without IPv4 fallback during
evaluations and acceptance testing. That network **SHOULD** be clearly marked,
rate-limited, and isolated from internal management zones; it complements jump
hosts but does not replace them for break-glass administration.

# Observability and Metrics {#observability}

IPv6 migration needs **inventory plus measurement**: a service list with IPv6
readiness labels, automated discovery of what is missing from that list, and
time-series metrics that show progress toward dual-stack or IPv6-only targets.

## Service Inventory and Discovery

The inventory in (#application-readiness) **MUST** list every application and
platform component with a readiness state (for example: IPv6-only ready,
dual-stack, IPv4-only, unknown). Inventory alone is not enough --- operators
**SHOULD** run periodic **discovery** that compares running processes, container
images, load balancer pools, and DNS names against the catalog and **flags
unregistered services**. Shadow deployments and shared hosts routinely run
software that no team has classified.

## Progress Metrics

Dashboards **SHOULD** expose fleet-level indicators, for example:

* Percentage of services **IPv6-only**, **dual-stack**, or **IPv4-only** (by
  count and by criticality tier)
* Trend of **AAAA vs A-only** DNS names for production hostnames
* Ratio of **ingress bytes or connections** over IPv6 vs IPv4 at load balancers
* Count of hosts or pods **without any IPv6 address** in IPAM or configuration
  management

Set explicit targets (for example, "90% of tier-1 APIs dual-stack by Q4") and
review the same metrics in change advisory boards.

## Dual-Stack Regression and Hard Failures on IPv6

Dual-stack is a valuable migration step, but **without monitoring it invites
regression**. A service that passed dual-stack testing can **stop working on IPv6**
after an unrelated code push --- for example, a new dependency, a changed bind
address, or a refactored HTTP client that silently prefers IPv4. Unmonitored
dual-stack fleets often **mask** such regressions because IPv4 still succeeds.

**Treat IPv6 failures as hard failures as soon as policy allows** --- alert on
IPv6-only health checks, IPv6 listen-socket regressions, and rising IPv4-only
connection share for tier-1 services. Where production remains dual-stack,
synthetic probes **SHOULD** exercise **IPv6 explicitly** (AAAA-only paths,
IPv6 literal targets, or IPv6-only test clients), not only dual-stack clients
that can hide breakage. The sooner IPv6 errors page on-call the same way IPv4
errors do, the less likely a team discovers IPv6 rot months later during an
IPv4 decommissioning drill.

Approved **IPv4-only exceptions** (see (#ipv4-only-exceptions)) are the controlled
counterpart to this policy: hard failure is the default; a documented waiver
with remediation timeline is the escape hatch, not silent dual-stack masking.

## Host-Level Listen-Socket Audit

On each host, collect which services **listen on IPv4-only**, **IPv6-only**, or
**dual-stack**. On Linux, `ss -tulnp` (or `/proc/net/tcp` and `tcp6`) is the
usual source, but classification is **non-trivial**:

* Separate `tcp`/`udp` vs `tcp6`/`udp6` lines are often **IPv4-only** vs
  **IPv6-only** listeners.
* A single IPv6 socket with `IPV6_V6ONLY=0` may accept IPv4-mapped traffic
  without a matching `tcp` line --- treat as **dual-stack** only after checking
  socket options or process documentation.
* Match rows by **PID, port, and inode** when correlating multiple lines for one
  daemon; export a normalized label (`v4-only`, `v6-only`, `dual-stack`,
  `unknown`) for metrics.

Run this audit on a schedule and on every deploy; alert when a tier-1 service
regresses to IPv4-only.

## Host Agents Before Application Provisioning {#host-agents}

Before any application software is installed, **inventory every agent and
daemon already running on the host** --- configuration management, monitoring,
log shippers, vulnerability scanners, **EDR**, host firewalls, and other
platform packages the fleet image includes by default. These components often
**bind IPv4-only**, ship IPv4-only policy from a central console, or break when
the host loses IPv4 even if the workload you plan to deploy is IPv6-ready.

Run this baseline check on **golden images and freshly provisioned servers**, not
only on production services. A host cannot safely move to dual-stack or
IPv6-only if an unknown agent still requires IPv4 loopback, RFC 1918 reachability,
or IPv4-only reporting to its controller. Export agent name, version, listen
sockets (see above), and **IPv6 readiness** into the same catalog as
(#application-readiness). Re-run when the image or security baseline changes.

## Traffic by Protocol and Address Family

Switches and routers expose **IPv4 and IPv6 packet counters** but often **do
not break out TCP and UDP by IP version** (TCPv4 vs TCPv6, UDPv4 vs UDPv6).
Where the platform allows, collect **`tcp4`/`udp4` vs `tcp6`/`udp6`** (or
equivalent flow records) on hosts, hypervisors, and top-of-rack devices.
Application SREs need **L4 metrics split by address family** to confirm traffic
is migrating and to find stragglers still on IPv4-only or translated paths.

Log pipelines **SHOULD** record address family explicitly (`AF_INET` vs
`AF_INET6`) rather than inferring from string shape.

## HTTP Signaling and Planned IPv4 Drills

For HTTP services, implementing [HTTP Signaling of Planned IPv4
Unavailability](https://datatracker.ietf.org/doc/draft-martin-retry-over-ipv6/)
(`566` responses, `Retry-Over-IPv6`, and related headers) gives **measurable
signals** during planned IPv4 outages: count `566` responses, soft vs hard
failures after IPv6 retry, and clients still hitting IPv4. That data belongs on
the same dashboards as listen-socket and byte-ratio metrics when rolling out
dual-stack or IPv6-only frontends.

## Live Traffic and Service Call Trees

Inventory and socket audits show **what could** run on IPv6; live traffic shows
**what does**. Instrument outbound and inbound connections (service mesh,
eBPF, proxy access logs, or APM) to tag each hop with **address family**.
Roll those tags into a **call tree or dependency graph per service** so teams
see, for example, "API gateway is dual-stack but 80% of backend calls still use
IPv4" or "this batch job is IPv4-only despite an IPv6-ready binary."

Use call-tree family breakdown to prioritize refactors: fix the highest-volume
IPv4-only edges first. Reconcile call-tree findings with the inventory --- a
service marked "IPv6 ready" with no IPv6 traffic is not done.

# Part II: Building the IPv6 Data Center

# Out-of-Band Management and Network Boot {#oob-management}

Software readiness is insufficient if servers cannot be **installed, booted, or
power-cycled** over IPv6. This area **SHOULD be tackled very early** in an IPv6
program --- before application tiers --- because **hardware refresh cycles can
take up to five years**. A server bought today with an IPv4-only baseboard
management controller (BMC) or provisioning stack may still block IPv6-only
operation long after application code is ready.

## Often-Forgotten Infrastructure Devices

Out-of-band work is not limited to compute **IPMI**, **Redfish**, and **PXE**.
Teams routinely overlook **facility and operations gear** that shares the same
management VLANs and must be reachable during incidents:

* **UPS** and power distribution monitoring
* **Climate control** (CRAC, chillers, environmental sensors)
* **NTP** appliances or stratum servers on dedicated hardware
* **Console servers** and serial concentrators
* **KVM switches**, rack PDUs, and other **data center infrastructure
  management** devices

These systems often ship with **fixed IPv4-only interfaces**, embedded web UIs
bound to `192.168.x.x`, and long firmware cadences. Include them in the same
IPv6 readiness inventory as production servers (see (#application-readiness) and
(#observability)); they become blockers during IPv4 decommissioning even when
every application pod is dual-stack.

## Firmware and PXE/UEFI Boot

Many **BIOS** implementations still lack usable IPv6. **UEFI network boot**
over IPv6 exists but **varies by server vendor** in ways that affect
automated provisioning. Network appliance **EFI** implementations are similarly
inconsistent. An IPv6-only provisioning VLAN requires explicit qualification of
every hardware generation in the fleet.

## IPMI and Redfish

**IPMI over IPv6** is **essential** for **remote power cycle and reboot** when
management networks move to IPv6-only. Without a working BMC address on v6,
automation cannot recover a hung host without a physical visit. The same
requirement applies to the **provisioning and reboot toolchain** --- imaging,
PXE/UEFI orchestration, configuration management kickstart, and out-of-band
serial concentrators **SHOULD** be **dual-stack or IPv6-only capable** before
internal management VLANs drop IPv4.

**IPMI** and **Redfish** IPv6 support differs by vendor and firmware generation:
some platforms support SLAAC, others DHCPv6, others require initial IPv4
configuration before enabling IPv6. Linux `ipmitool` subcommands and output
formats vary with firmware. Enterprises often **defer firmware upgrades** because
failed BMC updates require physical data center visits --- plan IPv6 on management
networks with spare in-rack capacity and conservative change windows.

# Internet and Data Center Addressing {#internet-addressing}

Network teams assign prefixes; SREs consume them in orchestration templates,
container runtimes, and firewall tickets. This section covers patterns that
reduce outages during rollout.

## Prefix Allocation for Hosts and Containers {#prefix-allocation}

A common data center pattern assigns a **`/56` to each physical host** (or
rack entity), providing **256 `/64` subnets** --- one `/64` for the host itself
and up to **255 `/64` prefixes** for containers, virtual machines, or
Kubernetes pods. Each container **SHOULD** receive a full **`/64`**, not a
longer prefix carved out of a single host `/64`. Routing between `/64` islands
replaces NAT for east-west traffic and avoids CGNAT-style visibility loss in
flow logs. Assigning only a **`/64` per host** (or per rack entity without
further delegation) is **often insufficient** when multiple containers each
need their own address space; request a **`/56` (or shorter)** delegation from
the network team instead. In a **closed data center** with explicit routing and
no SLAAC on container segments, some designs assign one **`/64` per physical
host** and carve **`/72` (or longer) subnets** from that host prefix for
container tiers. That pattern is **not** suitable on the public Internet or
where hosts expect standard `/64` semantics; use it only with operator-wide
agreement and tested CNI or orchestrator support.

The exact mapping depends on orchestrator and CNI design; the important software
lesson is that **each tier needs an explicit prefix plan** rather than assuming
"one address per host" as in legacy IPv4 NAT designs.

Kubernetes clusters often use eBPF-based service NAT on the node. Traditional
Linux tools (`ss`, `/proc/net/tcp`) may show node-level sockets, not pod-level
flows, when NAT is involved. IPv6 routing reduces NAT use --- which also
**reduces the complexity inherent in NAT when tracing connections** --- but
**does not remove the need for observability hooks** at the CNI layer.

## Static Addressing, Router Advertisements, and IPAM

Enterprise data centers usually prefer **static addresses** from an IP Address
Management (IPAM) system over SLAAC-derived random interface identifiers.
Disable **Router Advertisements (RA)** on server-facing **switch ports** (for
example by clearing the **Managed** and **Other** flags) **and** disable
**SLAAC** on **servers and other endpoints** when static addressing is required.
Applying both controls --- at the **network edge and on the host** --- provides
**two layers of protection** so hosts do not acquire unexpected addresses
alongside provisioned ones.

Gateway at **`fe80::1`**, global addresses from IPAM, and DNS names registered
in forward and reverse zones should be one coordinated change set.

## Semantic Prefixes for Internal Traffic {#semantic-prefixes}

On IPv4, operators quickly tell **internal from Internet** traffic: RFC 1918
space such as `10.0.0.0/8` and `192.168.0.0/16` signals "inside the
organization" in logs, captures, and mental models [@!RFC1918]. On IPv6, most
data center addresses are **global unicast** --- there is no automatic "private
vs public" heuristic. Debugging and ACL writing become harder unless the site
**designates a small set of well-known aggregates** in IPAM and teaches SREs to
use them.

A practical pattern is to carve **one prefix for each operational class**, for
example:

* **Everything in the data center** --- one aggregated prefix (the exact length
  depends on fleet size; a `/26` under the site GUA is an example when the
  block is purely semantic and routing summarizes wider internally)
* **Everything employees** --- corporate VPN, office wired/wireless for staff
* **Everything guest Wi-Fi** --- captive portal and untrusted clients

SREs then remember **three networks**, not hundreds of `/64`s, when filtering
pcaps, writing runbooks, or explaining an incident. Document these prefixes in
the same place as (#prefix-allocation) and (#acl-propagation) rules so logs,
firewall objects, and monitoring use consistent names (`dc-internal`,
`corp-employee`, `guest-wifi`).

**Internal data center prefixes SHOULD NOT be announced or routed to the
Internet.** When addresses are global unicast, **routing policy**
at the edge **SHOULD** filter site-internal aggregates so they remain reachable
only inside the operator network. Operators **MAY** suppress these GUA prefixes
from BGP advertisements if permitted by the relevant RIR and if such exclusion
does not cause unnecessary prefix de-aggregation. That routing boundary adds
**defense in depth** on top of firewalls: a misconfigured ACL or leaked route
is less likely to expose internal infrastructure to the public Internet.

Monitoring, security analytics, and log UIs **SHOULD** let operators **assign
visible colors or tags to semantic prefix ranges** --- for example, external
(Internet-facing) addresses in one color, data center internal prefixes in
another, and corporate or employee VPN ranges in a third. The exact palette is
operator choice; the goal is instant recognition in dashboards, alerts, and
pcap summaries without parsing every `/64`.

## Internet Egress and Edge Gateways {#internet-egress}

On IPv4 it is often convenient to give a data center host Internet access via
**NAT44** (or operator CGNAT) on a central device. That pattern **SHOULD NOT
be copied onto IPv6 hosts** --- do not deploy ad hoc **NAT66** or per-server
masquerading so internal servers "hide" behind random IPv6 ports. Internal
hosts **SHOULD** reach the Internet through a **gateway at the edge** (border
router, firewall, or dedicated translation cluster) with explicit policy and
logging.

That edge model still helps when an **IPv6-only server** must reach an
**IPv4-only Internet service**: the server sends IPv6 to the edge; the gateway
performs **NAT64** or protocol translation [@!RFC6146] (and DNS64 where
needed) on the way out. Translation is **centralized, observable, and
rate-limited** --- not duplicated on every app host.

## Internal vs External: Where IPv6-Only Applies {#internal-external}

A practical **IPv6-only data center** usually means **IPv6-only on internal
interfaces and east-west paths**, not on every interface facing the outside
world. The **Internet is not yet ready for an IPv6-only-only edge**: clients,
transit, partners, and operator tooling still expect **dual-stack** (or IPv4
fallback) on **external** interfaces --- load balancers, border routers, VPN
concentrators, and customer-facing anycast fronts.

Plan accordingly:

* **Inside the data center:** servers, containers, and service-to-service traffic
  **SHOULD** move to **IPv6-only** (or IPv6-primary) on internal VLANs and
  `/64` islands as readiness allows.
* **At the edge:** **external interfaces SHOULD remain dual-stack** until IPv4
  dependency is gone for your user base and upstream paths. The edge gateway
  performs translation when an internal IPv6-only host must reach IPv4-only
  destinations (see above).

**Dual-home servers on the edge** --- one **internal** interface (IPv6-only or
IPv6-primary) and one **external** interface (dual-stack) --- simplify
**administration and break-glass access**: operators and automation can reach
management paths on the internal v6 network while the service still serves
dual-stack Internet clients. Document which interface is which in IPAM and
host naming; do not collapse "internal v6-only" and "external dual-stack" into
a single ambiguous address on production boxes. During migration, the internal
interface may remain **IPv4-only** for a time; see
(#dual-homed-transitional-routing) for routing and DNS pitfalls on those hosts.

### Dual-Homed Hosts During Internal IPv6 Rollout {#dual-homed-transitional-routing}

Edge servers often have **two interfaces**: an **external** interface toward the
Internet (dual-stack, **default route**) and an **internal** interface toward the
data center (today **IPv4-only**, with **more-specific routes** for internal
prefixes). That layout is common during brownfield migration before the internal
VLAN gains IPv6 on every host.

When internal services begin publishing **AAAA** records, a dual-homed host that
still has **no IPv6 on the internal interface** may resolve both A and AAAA for
an internal name but send IPv6 connection attempts out the **default route** on
the external interface. Those packets never reach the internal service. Symptoms
include **long timeouts** on dual-stack clients, flaky automation, and "internal
DNS works from other hosts but not from the edge box."

Operators **SHOULD** align **routing policy with DNS**, not assume AAAA implies
a working IPv6 path from every interface:

* **Preferred long-term:** enable IPv6 on the internal interface and install
  **scoped routes** (or policy routing) so internal GUA prefixes egress the
  internal interface (see (#semantic-prefixes)).
* **Transitional mitigation:** while the internal NIC remains IPv4-only, install
  an **`unreachable`** route for the site **internal IPv6 aggregate** on the host
  (for example, the `dc-internal` prefix from (#semantic-prefixes)). The kernel
  then rejects connection attempts to internal AAAA addresses **immediately**
  with a local "no route to host" error instead of forwarding them via the
  Internet default route. Clients that iterate all resolved addresses --- or use
  Happy Eyeballs [@?RFC8305] --- can fall back to the **A** record over the
  internal IPv4 path (see (#name-resolution)). Do **not** use a **`blackhole`**
  route for this purpose: blackhole **silently discards** packets and recreates
  the same **timeout** behavior the operator is trying to avoid.
* **Alternative:** **split-horizon DNS** so resolvers used on edge hosts do not
  return AAAA for names that are reachable only on the internal IPv4 path until
  routing is fixed.

This pattern is **not** a substitute for enabling IPv6 on internal interfaces;
it prevents **misrouted IPv6** during rollout. Application code that stops after
the first address (`gethostbyname()`, `InetAddress.getByName()`, and similar)
**will not benefit** --- fix routing **and** resolution behavior together.

Example (Linux, illustrative prefix):

    ip -6 route add unreachable 2001:db8:dc::/48

Express the same policy in configuration management on every dual-homed edge
role during the transition; remove the unreachable route when the internal
interface is dual-stack and correct scoped routes are in place.

## Frontends for IPv4-Only Services {#ipv4-only-wrappers}

Legacy applications that remain **IPv4-only** **SHOULD NOT** be exposed
directly to dual-stack or IPv6-only clients. Surround them with a **gateway
tier** --- for example **nginx**, **HAProxy**, or a service-mesh ingress ---
that accepts **IPv6 (and IPv4 if required)** on the front side and speaks IPv4
only to the backend. Clients see a normal v6-capable service name; the
IPv4-only binary stays on an internal path until it is rewritten or replaced
(see (#provision-not-transform)).

In dual-stack deployments where session persistence is required, SREs **MUST**
verify that the gateway tier preserves session continuity across both IPv4 and
IPv6. Implementations that maintain separate persistence state for each address
family may experience session loss when clients alternate between IPv4 and IPv6.

An alternative on the host is **NAT64 implemented with eBPF** (similar in spirit
to Kubernetes node NAT). That can unblock a single service quickly but **often
does not scale** as a fleet-wide strategy --- connection state, troubleshooting,
and upgrade churn multiply with every host doing translation. Prefer a **small
number of shared frontends or edge translators** over per-host NAT64 except in
controlled exceptions. See also (#icmpv6-pmtud) for VPN and middlebox
interactions with translated traffic.

## Access Control List Propagation {#acl-propagation}

When IPv6 is added to a service that already runs on IPv4, **firewall and ACL
automation may lag by minutes**. During that window the service can appear
**healthy on IPv4 but broken on IPv6**, or reachable in one direction only.
SRE runbooks **SHOULD** treat "IPv6 enabled on the host" and "IPv6 permitted
end-to-end" as separate checklist items. Do not announce IPv6 on a load
balancer until policy propagation completes.

Software teams **SHOULD NOT** create entirely new ACL models per address family
when the same role-based policy can express both; parallel rule sets double
drift risk. Where separate rules are unavoidable, generate them from the same
source of truth.

### IPAM-Based IPv4-to-IPv6 Mapping for ACLs

When IPAM tracks both address families, operators can **derive a predictable
IPv6 address from a hostname** before an AAAA record exists in DNS. That
mapping lets ACL and firewall systems publish **IPv6 rules in advance**, so
policy is already in place when the service starts listening on IPv6 --- there
is no window where the host is up on IPv6 but ACL automation is still catching
up.

This pattern **requires ACL policy to be expressed by hostname (or role)**, not
by scattered literal addresses maintained separately per family. Given a hostname,
a controller can resolve or derive addresses with the following **pseudo-rules**:

1. Look up the **AAAA** record. If present, use that IPv6 address.
2. If no AAAA exists, look up the **A** record and obtain the IPv4 address.
3. In IPAM, find the **IPv4 network** that contains that address.
4. Find the **associated IPv6 network** paired with that IPv4 network in IPAM.
5. **Embed the IPv4 address** into the IPv6 network according to the site's
   translation plan (for example, a fixed nibble layout or well-known offset).
   The result is the **predicted IPv6 address** for that hostname.

The benefit is operational: **ACLs for IPv6 can be built and deployed everywhere
before DNS advertises AAAA**, because the IPv6 address is computable from the
same hostname and IPAM data already used for IPv4. When the service later
enables IPv6 and the AAAA is published, the pre-provisioned rules should match
without a second ACL rollout. The site translation plan in step 5 **MUST** be
documented and stable; ad hoc embedding layouts defeat this approach.

The same correlation policy supports an **early dual-stack step on the host**
without advertising **AAAA** in DNS. IPAM assigns the predicted IPv6 address on
the interface; the application tier can remain **IPv4-only** (A record only,
IPv4 listen sockets) while **outbound** traffic from the host uses IPv6. That
lets platform agents --- configuration management, monitoring, log shippers,
vulnerability scanners, and other infrastructure daemons (see (#host-agents))
--- reach **IPv6-only** services on the fabric before application code is
ready. Inbound clients still use IPv4 until a deliberate cutover adds AAAA and
dual-stack or IPv6-only listeners; pre-provision ACLs and routing for the
predicted v6 address using the steps above.

If ACL systems cannot accept hostnames and expand them through this logic,
teams fall back to the lag problem described above --- IPv6 goes live while
firewall tickets are still in flight.

# DNS Registration and Dynamic Addressing {#dns-registration}

IPv6's default autoconfiguration (SLAAC) generates addresses from interface
identifiers. Without operational discipline, **DNS lags behind actual
addresses**, and break-glass access by name fails.

## SLAAC, Switches, and the DNS Gap

Wi-Fi controllers often integrate with DNS to register client names; **access
switches frequently do not**. To populate DNS for wired servers using SLAAC,
operators need **MAC and address visibility** from switches (for example, via
Neighbor Discovery logging or sFlow/IPFIX) correlated with inventory to derive
hostnames. Ideally, selected **Neighbor Discovery events** would be exported to
a registration service --- a gap in many switch implementations.

## DHCPv6 and Hostname Registration

Enterprises that distrust client self-registration prefer **DHCPv6** with
central lease logging. Clients **SHOULD** send **DHCPv6 Option 39 (Client
FQDN)** so the server can register forward and reverse DNS [@!RFC4704]
[@!RFC8415]. Support for Option 39 has varied by OS; operators **SHOULD**
verify current behavior on every deployed OS image (including macOS, Windows,
Linux, and container base images) rather than assuming parity.

Device-side **Dynamic DNS updates** remain possible but are often disabled in
enterprise policy. For why reverse zones matter during incidents, see
(#network-diagnostics).

## DHCPv6 Suitability Considerations

DHCPv4 is extremely common in IPv4 deployments, as it is best mechanism
to automatically provide network information (such as IP address, 
router, netmask, recursive DNS resolvers) to nodes.  This, combined
with a desire to have centralized logging of assigned addresses, leads
to a desire for DHCPv6 in new IPv6 deployments.  However, IPv6 includes
much of this functionality in the base protocol; a central server is not
needed. Moreover, operating system support for DHCPv6 is not as
universal as for DHCPv4, so it is not a full replacement for SLAAC.  This
means that using DHCPv6 for centralized logging of addresses or DNS
synchronization either means that some clients may be logged (as they will
use SLAAC), or some clients may not work at all (if SLAAC is disabled on
the network).  Operators **SHOULD** verify DHCPv6 support for all existing
and planned hardware before relying on it for logging features.

# Hybrid On-Premise and Cloud Environments {#hybrid-cloud}

This section is **in scope** for operator-owned data centers that **connect to**
public cloud; it is **not** a guide to replacing the data center with IaaS or to
running production workloads **inside** provider-controlled virtual networks.
Native IPv6 deployment on AWS, Azure, GCP, or other platforms belongs in
provider documentation or a separate document --- prefix sizes, subnet models,
managed services, and control-plane IPv6 support differ by vendor, region, and
SKU in ways no single recommendation can capture. The material below **does**
matter for on-premise migration: cloud dependencies, private connectivity, and
provider IPv6 gaps routinely block or reshape IPv6-only programs on
operator-managed fabric even when compute stays in the physical data center.

Most enterprises are not pure on-premise: data centers connect to **public
cloud** providers (AWS, Azure, GCP, and others) for burst capacity, managed
services, disaster recovery, and SaaS integration. **IPv6 support across cloud
control planes and managed services is seldom complete** --- capabilities differ
by provider, region, SKU, and release. Hybrid gap analysis belongs in **Part I
inventory and early program planning**, not a discovery phase after the
on-premise fabric is already IPv6-only.

## Connectivity Models

Migration design **depends on how on-premise reaches cloud**:

* **Centralized gateway or cloud edge** --- on-premise workloads reach cloud APIs
  and resources through a **narrow path**: site-to-site VPN, Direct Connect,
  ExpressRoute, Cloud Interconnect, transit gateway, or operator translation at
  the border (see (#internet-egress)). IPv6 may terminate at that gateway; an
  internal v6-only host might reach cloud only via a dual-stack hub or
  translation. Prefix plans, ACLs, DNS views, and observability probes must
  anchor on that **choke point**.
* **Direct or flat hybrid routing** --- on-premise and cloud workloads share
  **routable reachability** (extended L3, cloud CIDRs advertised into the DC,
  cross-site service mesh). **Any host may connect to any cloud instance** on
  the allowed paths; IPv4 and IPv6 **must both be validated end-to-end**, including
  cloud VPC/VNet IPv6 CIDRs, security groups, network ACLs, private endpoints,
  and on-premise firewall policy.

Document which model each environment uses **before** declaring internal
IPv6-only. A data center that is v6-only on the fabric but cloud-connected only
through an **IPv4-only VPN or private link** still depends on translation or
exceptions at the edge --- a common hidden blocker.

## Cloud Provider Gap Analysis

Cloud portfolios change frequently. Operators **SHOULD** maintain a
**provider-specific IPv6 matrix** for every service in use --- compute, load
balancing, databases, object storage, key management, logging, identity, managed
Kubernetes control planes, firewalls, WAF, PrivateLink-style endpoints, and
inter-region peering --- with **supported / partial / unsupported / unknown**
labels and notes on **region, tier, and verification date**.

**Identify blockers early:** review architecture diagrams and infrastructure-as-code
for implicit IPv4 assumptions (RFC 1918-only security groups, IPv4 health checks,
managed endpoints without AAAA, IPv4-only egress appliances). Open **provider
support cases and feature requests** as soon as a required service lacks IPv6 ---
enterprise cutover dates cannot wait for roadmap surprises discovered in production.
Where IPv6 exists only in select regions or SKUs, record that constraint in the
inventory and use (#ipv4-only-exceptions) when the business must stay on IPv4-only
cloud paths temporarily.

## Cloud as Platform Software

From the data center team's perspective, **cloud is platform software the business
cannot fully control** --- APIs, quotas, and feature availability change on the
provider's schedule. Apply the same discipline as (#application-readiness): list
each cloud dependency in the fleet inventory, assign IPv6 readiness labels, and
**raise gaps before platform adoption**, not after teams have built on IPv4-only
managed services.

Hybrid programs **SHOULD** include **cloud account and landing-zone reviews** in
the same governance cadence as on-premise migration metrics (see (#observability)).
A service marked "IPv6-ready on-premise" that calls an **IPv4-only cloud API** or
runs on an **IPv4-only managed control plane** is not ready for internal v6-only
operation. Treat cloud like any other long-lead vendor: inventory, support
tickets, and exception tracking **SHOULD** start at program kickoff.

# ICMPv6, PMTUD, and Middleboxes {#icmpv6-pmtud}

## Do Not Block ICMPv6

Teams trained to block ICMPv4 "for security" sometimes apply the same policy
to ICMPv6. **ND and PMTUD depend on ICMPv6** [@!RFC4443] [@!RFC8201]. Blocking
ICMPv6 produces hung connections, mysterious TLS timeouts, and DNS failures
that are misdiagnosed as application bugs. Filter **specific message types**
judiciously; do not implement blanket deny rules. For **echo request/reply**
used in reachability testing inside the data center, see (#network-diagnostics).

## Path MTU Discovery

When many organizations enabled IPv6 on their web sites during **World IPv6 Day**
(2011) and **World IPv6 Launch** (2012), **Path MTU Discovery failures** forced
operators to **lower TCP MSS** on servers and load balancers until paths were
validated --- a reminder that IPv6 MTU assumptions differ from internal IPv4
MTU 1500 end-to-end paths. Mobile operators (for example, T-Mobile USA and
Reliance Jio in India) run **IPv6-only** access networks successfully at scale;
problems on enterprise fixed networks often come from **middleboxes and
policy**, not from IPv6 itself.

Hard PMTUD failures also interact with **DNS over large responses** when
fragmentation is mishandled. If fragmented UDP is dropped, DNS appears
"flaky" only for some records.

## VPNs and NAT64

Some VPN products treat translated packets as attacks. **NAT64** [@!RFC6146]
changes headers; a VPN that validates packet integrity on IPv4 paths may **drop
NAT64 flows**. Prefer **edge gateways** for translation as described in
(#internet-egress) and (#ipv4-only-wrappers) rather than sprouting translators on
every host. Long-term, **VPN endpoints should be native IPv6** on the data
center side. Until then, document which access paths require IPv4 literal
connectivity vs IPv6.

# Application and Software Readiness {#application-readiness}

IPv6 deployment exposes software that "worked on the LAN" only because the LAN
was IPv4. This section lists classes of problems seen in production data
centers and enterprise rollouts.

## Enterprise Platform Inventory

Many enterprise platforms still assume IPv4-only access paths. Examples
reported in operator experience include **Hadoop**, certain **object storage
APIs**, **Kubernetes** dependencies (especially third-party charts and
sidecars), **cloud firewalls** (for example, Azure Firewall and third-party
NGFW images on cloud platforms where IPv6 support lagged vendor roadmaps), and
**security analytics** pipelines that ingest NetFlow or packet metadata on
IPv4 only. Hybrid and multi-cloud estates need the same inventory discipline
for managed services and connectivity paths (see (#hybrid-cloud)).

**Action for SRE teams:** maintain a **living inventory** of software in the
deployment path (data plane, control plane, CI/CD, security, logging) with an
explicit **IPv6 supported / broken / untested** classification. Monitoring
pipelines **SHOULD** continuously **discover services not yet in that inventory**
(see (#observability)). Security research or monitoring that runs IPv4-only
cannot validate IPv6 attack surface; teams **SHOULD** require IPv6 parity before
accepting "no IPv6 security issues" claims.

This document does not attempt a canonical vendor matrix --- products change
--- but the inventory practice is mandatory for sane rollout planning.

## Dependency and Platform Readiness Gates

Many SREs and software engineers **will not** study address representation,
`getaddrinfo()` semantics, or Happy Eyeballs in depth --- and should not have
to before every deploy. Platform teams **SHOULD** publish **monitored readiness
gates**: for each shared dependency (language runtime, HTTP/RPC client, database
driver, messaging library, observability agent, base container image), document
a **minimum version or image tag** validated on dual-stack and IPv6-only paths.
Example gate: *upgrade **`example-http-client` to 2.4.0 or newer** --- then the
service is cleared for IPv6*; versions below the threshold remain **blocked or
flagged** in the inventory until upgraded.

**Automate enforcement** against that catalog: compare SBOMs, lockfiles, image
scans, and configuration-management reports to the matrix on a schedule and in
CI (see (#observability)). When a service crosses the threshold --- dependency
bumped, agent replaced, golden image refreshed --- **update its readiness label**
without requiring every engineer to audit socket call sites by hand. Put the gates
where teams already work (service catalog, Renovate or equivalent dependency
bots, deployment checklists) and **SHOULD** tie change-advisory or promotion
policy to them so **unknown** or **below-minimum** software cannot reach
production dual-stack or IPv6-only paths unnoticed.

## Developer and Pre-Production Environments {#dev-environments}

**Provide dual-stack (and eventually IPv6-only) networks to developers as early
as possible** --- ideally before production rollout, not after. Engineers who
code and debug only on IPv4-only laptops or lab VLANs ship software that
"works in the office" and fails when AAAA records appear in production.

It is customary to **build and test new code in VMs or containers** that mirror
production topology before release. Those evaluation environments **MUST**
include **dual-stack** and **IPv6-only** variants alongside legacy IPv4-only
images where brownfield support is still required. CI pipelines **SHOULD** run
integration tests against both address-family modes so a code push cannot
silently regress IPv6 without failing the build.

Platform teams **SHOULD** publish standard developer network profiles (dual-stack
lab, IPv6-only sandbox, simulated edge with NAT64) and document how to attach
local IDEs, test harnesses, and AI coding agents to them.

## Hard-Coded Addresses and Localhost Pitfalls

A recurring defect is binding services to **`127.0.0.1`** instead of
**`localhost`**. On dual-stack hosts, `127.0.0.1` listens **IPv4
loopback only**; IPv6 clients cannot connect even when the service "runs
locally." The fix is to use name-based bind targets (`localhost`) or explicit
dual-stack sockets depending on platform API.

Similar bugs appear with **`0.0.0.0`** vs **`::`** listen semantics, health
probes that curl IPv4 literals, and container images that ship `/etc/hosts`
without IPv6 entries.

## IP Address Storage in Application Data

Many services store client or server IP addresses in databases, logs, caches,
and message queues using **fixed-width fields** (32-bit integers, `CHAR(15)`)
or parsers that accept dotted decimal only. IPv6 requires **structured address
types** (128-bit binary, or text with adequate length) and family-aware
comparison.

Affected areas include:

* **Geolocation databases** (for example, MaxMind and similar) used for
  compliance, fraud, and ad targeting --- coverage and accuracy for IPv6 vary
  widely.
* **Real User Monitoring (RUM)** and **DNS steering** products that map clients
  to "nearest" PoP --- if the probe or edge logic is IPv4-only, steering
  decisions silently degrade for IPv6 clients.
* **Rate limiting and abuse detection** keyed on "IP" strings with naive
  splitting on `.` characters.

Refactoring often touches every schema, serializer, and analytics job that
touched the field --- plan migration as a **program**, not a one-line fix.

## Databases, ACLs, and Security Tools

**MySQL and MariaDB** host-based ACLs are historically **string comparisons**
on the client address field. IPv6 literals contain colons and zone identifiers;
copying IPv4 ACL patterns without testing produces false denials or overly
broad grants. Test `USER@'2001:db8::/32'`-style entries explicitly.

Security agents (EDR, IDS, WAF) may lack IPv6 decode paths even when they claim
dual-stack support. Validate **both directions** --- ingress to the service and
egress from the service --- under IPv6-only client paths. The same teams can
extend PR checks with static analysis rules (see (#static-analysis)).

## Language Runtimes and Libraries {#language-runtimes}

**Python** exposes several **deprecated socket helpers that are IPv4-only or
return only one address**, yet remain common in production code and older
tutorials. Examples include:

* **`socket.gethostbyname()`** and **`socket.gethostbyname_ex()`** --- resolve
  a name to IPv4 only; use **`socket.getaddrinfo()`** and iterate all results
  (see (#name-resolution)).
* **`socket.gethostbyaddr()`** --- reverse lookup with IPv4-centric assumptions;
  prefer **`getnameinfo()`** with a binary `sockaddr` from the connection.
* **`socket.inet_aton()`** and **`socket.inet_ntoa()`** --- convert IPv4
  literals only; use **`socket.inet_pton()`** and **`socket.inet_ntop()`** for
  both address families.

These APIs **will not return IPv6** even when the host has AAAA records and
IPv6 connectivity. Replacing them is rarely a one-line change --- call sites,
tests, and error handling often assume 32-bit or dotted-decimal form.

Other languages have similar legacy (`inet_aton` assumptions, IPv4-only standard
library gaps). Code review checklists **SHOULD** include:

* No unparsed string IPs in business logic
* Resolve names with a **full-list** API (see (#name-resolution)); never call
  legacy one-address helpers in new code
* Tests that run against **IPv6 literals and DNS names with AAAA records**

## Static Analysis and Pull Request Automation {#static-analysis}

Manual review does not scale across large monorepos. **Security and platform
teams SHOULD integrate IPv6 readiness checks into pull request (PR) workflows**,
piggybacking on existing gates rather than relying on a separate audit cycle.

### Pattern Scanners in CI

Ship **Semgrep**, **CodeQL**, or equivalent rules that flag likely IPv4-only
patterns, for example:

* Literal `127.0.0.1`, `0.0.0.0`, or dotted-decimal regexes used as addresses
* Calls to deprecated Python socket helpers (see (#language-runtimes))
* `AF_INET` sockets where dual-stack or `AF_INET6` is required
* Database columns or structs sized for IPv4-only (`CHAR(15)`, 32-bit integers)
* String splits on `.` to parse "IP addresses"

Security teams often own the rule pack; application teams own remediation.
Rules **SHOULD** be published internally with examples and fix guidance.

### Automated Remediation Pull Requests

Beyond blocking merges, pipelines **MAY** open **automatic PRs** that propose
fixes when a scan finds matches on default branches or on a schedule. Some
findings are straightforward (replace `gethostbyname` with `getaddrinfo` usage);
others need context. **AI-assisted patch generation** can speed up bulk
refactors, but **MUST** be reviewed by a human --- expect **false positives**
(for example, code that intentionally handles IPv4-only legacy clients).

Treat auto-generated PRs like any other contribution: tests, ownership by code
owners, and rollback plan.

### Opt-Out Annotations for Engineers

Engineers **SHOULD** be able to **suppress a finding on a specific line** when
the IPv4-only behavior is intentional and documented --- for example, a
compatibility shim with a planned removal date. Define a **codified comment**
recognized by the scanner, placed **immediately before** the flagged line. An
example directive:

    # ipv6-readiness: ignore-next-line -- see TICKET-123

The project **MUST** document the exact directive string, required rationale
format, and whether ticket references are mandatory. Blanket disables of entire
files **SHOULD NOT** be allowed without security team approval.

### AI Coding Agent Skills

Many teams now use **AI coding agents** in the IDE and in CI. Add an **IPv6
readiness skill** (or equivalent project rule) to the agent environment --- and
**push the same skill into application repositories** --- so generated patches
default to **dual-stack APIs**, **`getaddrinfo()`-style resolution**, and
IPv6-safe listen/bind patterns. The skill **SHOULD** require agents to verify
that new network code works when AAAA records are present and when IPv4 is
absent (IPv6-only paths). Treat this as part of the same program as Semgrep
and CodeQL rules, not a substitute for automated tests on dual-stack and
IPv6-only runners (see (#dev-environments)).

## Documentation and Presentations {#documentation-examples}

Runbooks, architecture diagrams, wikis, training decks, and conference slides
**SHOULD use IPv6 addresses in examples by default**, unless the example is
inherently IPv4-specific. Using IPv4-only literals in internal documentation
normalizes the wrong protocol for new engineers and hides gaps until production
rollout. IETF documents follow the same principle: examples **SHOULD** use IPv6
and reserved documentation prefixes rather than arbitrary or production
addresses [@!RFC3849] [@!RFC5737].

When an example needs an IP address or prefix, follow **IETF documentation
address rules**:

* **IPv6 (preferred):** use the documentation prefixes reserved in [@!RFC3849]
  (`2001:db8::/32`) and [@?RFC9637] (`3fff::/20` for larger or more realistic
  layouts). Represent addresses in **canonical text form** per [@!RFC5952]
  (lowercase hex, suppress leading zeros, use `::` compression).
* **IPv4 (only when required):** use the TEST-NET blocks in [@!RFC5737]
  (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) --- not production
  space, arbitrary `10.0.0.0/8` lab subnets, or other unreserved ranges that
  could collide with real deployments.
* **Names:** use example domain names from [@?RFC2606] (`example.com`,
  `example.net`, `example.org`) rather than real operator domains.

Review documentation the same way code is reviewed: a slide full of `10.x.x.x`
or `192.168.x.x` examples teaches habits that conflict with IPv6-first data
center operation. Prefer `2001:db8:...` and service names unless the document
explicitly covers legacy IPv4 behavior.

# Resolving Hostnames to Addresses {#name-resolution}

This section covers name-to-address APIs and client resolution behavior --- the
connection layer above application readiness gaps cataloged above.

Turning a hostname into addresses is a separate step from choosing which
address to connect to. Application code **MUST** use an API that returns **all**
candidate addresses, then apply local policy (retries, Happy Eyeballs
[@?RFC8305], load spreading --- see (#address-selection) and
(#client-load-balancing)). When implementing Happy Eyeballs, **delay the IPv4
connection attempt** so IPv6 has more time to succeed first --- a late start for
IPv4 is consistent with [@?RFC8305] and reduces accidental IPv4-first behavior
on dual-stack paths.

Even with correct client retry logic, **missing or wrong IPv6 routes** can send
internal AAAA targets out an Internet default route. Edge hosts in transitional
layouts **SHOULD** install **`unreachable`** routes for internal aggregates so
address-family fallback can succeed (see (#dual-homed-transitional-routing)).

## Use getaddrinfo(), Not Legacy One-Address APIs

On POSIX systems the correct resolver entry point is **`getaddrinfo()`**
[@!RFC3493]. It takes a hostname (or numeric address string), service/port hints,
and an `addrinfo` hints structure, and returns a **linked list of `addrinfo`
structures** --- one node per address. The caller **MUST iterate the entire
list** (the `ai_next` chain), copy each `sockaddr` into binary form (see
(#address-representation)), and **MUST** release the list with `freeaddrinfo()`.

Please note: **`getaddrinfo()`** is the name-to-address API for retrieving a
full list; it is not the same as:

* **`gethostbyname()`** and **`gethostbyname2()`** --- deprecated, not
  thread-safe, and still present in old tutorials. Many call sites use only the
  first address even when multiple are available.
* **`inet_addr()`**, **`inet_aton()`**, and **`inet_pton()`** --- parse a
  **literal** address string into binary; they perform **no DNS lookup** and
  return a single address only.
* Higher-level HTTP or RPC helpers that resolve a name internally and connect to
  **one** chosen address without exposing the full set --- fine for quick
  clients, unsuitable when the service relies on multiple A/AAAA records.

To request both IPv4 and IPv6 results, set `hints.ai_family` to `AF_UNSPEC`
(unless a deliberate single-family policy applies). Inspect `ai_family`,
`ai_addrlen`, and `ai_addr` on **each** list element; do not assume every node
has the same address family.

Language runtimes expose the same idea under different names:

* **Python:** `socket.getaddrinfo()` returns a list of tuples --- iterate all
  entries; avoid `socket.gethostbyname()`, which returns one IPv4 address.
* **Go:** `net.DefaultResolver.LookupIPAddr()` or `LookupIP()`; avoid code paths
  that stop after the first returned address.
* **Java:** `InetAddress.getAllByName()` returns an array; **`getByName()`**
  returns only the first address and is a common source of "works in the lab"
  failures under round-robin DNS.
* **Node.js:** `dns.promises.resolve()` or `dns.lookup()` with `{ all: true }`;
  the default `lookup()` without `all: true` returns a single address.

Pay special attention when connecting to a **hostname** (as opposed to a numeric
literal): resolution can return both IPv4 and IPv6 addresses, and often more than
one of each. A failed `connect()` to **one** of those addresses does **not**
mean the host is unreachable. Application code **MUST NOT** report the
destination as down after trying only the first AAAA or A record and never
the other family, or after IPv4 fails while unused IPv6 candidates remain (and
vice versa). Try other addresses from the resolved list --- or use Happy Eyeballs
[@?RFC8305] --- before concluding that the service cannot be reached.

## Why the Full List Matters

DNS often publishes **multiple A and AAAA records** for availability and load
distribution. Connecting to `result->ai_addr` and ignoring `ai_next` defeats
that design. After collecting the list, the application (or a shared library)
chooses order: IPv6-first, Happy Eyeballs, random shuffle within a family, or
explicit retry on failure. **`getaddrinfo()` supplies candidates; it does not
replace client-side load balancing.**

Note that libc implementations may **reorder** the list per [@!RFC6724] before
returning it (see (#address-selection)). You still need every element --- reorder
yourself if policy requires --- but you cannot skip resolution and hope DNS
order survives unchanged.

## Numeric Input at the Edge

When configuration or user input contains an address **literal** rather than a
hostname, **`inet_pton()`** (or the language equivalent) converts it to binary
for storage. When input might be either a name or a literal, **`getaddrinfo()`**
accepts both; alternatively, try literal parse first, then fall back to DNS.
Either way, convert once to binary and use binary forms internally.

## Address Selection, gai.conf, and DNS Round Robin {#address-selection}

The Linux file `/etc/gai.conf` and the algorithms in [@!RFC6724] control
**address selection order** for dual-stack hosts --- which address family and
which destination address are tried first. This is invisible in application
source but visible in production load distribution.

**RFC 6724 destination address selection Rule 9** ("Use longest matching
prefix") compares each candidate destination with its likely source address
and **sorts addresses deterministically** [@!RFC6724]. Resolver libraries such
as **glibc** implement this sorting inside `getaddrinfo()`. The effect:
**DNS round-robin is not a load-balancing strategy on IPv6** (and is weakened
on IPv4 in many cases). A round-robin AAAA record can collapse to "always try
the same address first" once Rule 9 runs, concentrating connections on one
backend. The problem is subtle on IPv4 but **often severe on IPv6**.

Rule 9 is reasonable on the global Internet but **often wrong inside a data
center**, where many servers are functionally declared equidistant and
operators expect DNS or
anycast to spread load. Mitigations include:

* Perform **client-side load balancing** in the application or library.
* Fetch all addresses (for example, via `getaddrinfo()` without premature
  sorting, or via a resolver that preserves DNS order), then choose randomly
  **within the same address family** --- do not shuffle v4 and v6 together in
  ways that accidentally defeat IPv6 preference policy.
* Use service meshes, anycast, or explicit endpoint lists rather than naive
  round-robin alone.

Changing `/etc/gai.conf` adjusts precedence tables but **does not fully
disable Rule 9** in all implementations. Treat load balancing as a **software
concern**, not something DNS alone provides.

## Runtime-Specific Resolution (Not Always glibc) {#runtime-resolution}

Examples above assume POSIX **`getaddrinfo()`** via **glibc** (or an equivalent
libc). Not every language or runtime uses libc for name resolution. **Java**
maintains its own resolver stack and system properties such as
**`java.net.preferIPv4Stack`** and **`java.net.preferIPv6Addresses`** that
override address-family preference independently of `/etc/gai.conf`. A JVM
configured to prefer IPv4 can appear "IPv6 broken" even when the OS resolver
returns AAAA records. Test Java services with explicit property settings and
with **`InetAddress.getAllByName()`**, not **`getByName()`**.

In extreme cases, an **`/etc/resolv.conf`** that lists **only IPv6 nameserver
addresses** can interact badly with runtimes that bootstrap DNS over IPv4 first
or assume a v4-reachable resolver path. Symptoms include slow resolution,
timeouts, or unexpected family ordering. Qualify resolver configuration on
dual-stack and IPv6-only hosts for each runtime in the fleet, not only for C
callers of `getaddrinfo()`.

# Client-Side Load Balancing {#client-load-balancing}

Client-side load balancing builds on the resolution patterns in (#name-resolution)
when services publish multiple A/AAAA records.

As described in (#address-selection), **RFC 6724 Rule 9** reorders addresses
returned from DNS. In data centers that rely on multiple AAAA records for
spread, connection counts can skew badly --- one backend receives most IPv6
connections while others appear idle. This section assumes the application has
already obtained the **full address list** using the patterns in
(#name-resolution).

**Recommended pattern:**

1. Resolve the service name to all addresses.
2. Partition addresses by address family.
3. Apply family preference policy (operator choice: IPv6-first, happy eyeballs,
   or parallel). For Happy Eyeballs, **start IPv4 attempts after a deliberate
   delay** so IPv6 connections have priority time to complete.
4. **Randomize or round-robin within each family** rather than trusting DNS
   order after `getaddrinfo()`.
5. Optionally implement retries across the full set on failure.

Implement load balancing in **shared client libraries** so every service does
not rediscover the same RFC 6724 interaction.

# Network Diagnostics in the Data Center {#network-diagnostics}

A data center is a **closed, operator-controlled environment**. Two practices
that help SREs diagnose routing, DNS, and reachability problems on **both IPv4
and IPv6** are often skipped because they feel optional or risky.

## Reverse DNS

Maintain **forward and reverse DNS** for long-lived infrastructure: servers,
load balancers, management interfaces, and other addresses that appear in logs,
firewall hits, flow records, and packet captures. Reverse zones (**PTR** for
IPv4, **ip6.arpa** for IPv6 [@!RFC3596]) map an address back to a hostname.
That mapping is routine on IPv4 but becomes **essential on IPv6**, where
prefixes are not human-scannable and incidents otherwise devolve into comparing
128-bit literals. Reverse records **SHOULD** be created in the same change
workflow as forward records and IPAM assignments (see (#dns-registration)).
Spot-check with `dig -x` or equivalent on both address families before relying
on reverse lookup during an outage.

## Controlled ICMP Echo (Ping)

Teams trained to drop **ICMP echo request/reply** ("ping") on the public Internet
sometimes apply the same rule everywhere. **Inside the data center**, allowing
echo request/reply **with limits** --- rate limits, scoped ACLs, source
restrictions to management networks or jump hosts, or equivalent controls --- is
**RECOMMENDED** for troubleshooting. A successful or failed ping quickly
separates "no route" from "route but service down" on both IPv4 and IPv6 without
opening application ports.

This is separate from the ICMPv6 requirements in (#icmpv6-pmtud): Neighbor
Discovery and Path MTU Discovery need specific ICMPv6 types on production paths
and **MUST NOT** be blocked wholesale. Controlled echo is an additional
**diagnostic convenience** on top of that baseline. Operators **SHOULD NOT**
replace protocol-required ICMP with echo-only rules, nor block echo in ways that
remove a basic reachability tool from on-call engineers. Apply the same
philosophy to **ICMPv4 echo** inside the fabric: constrain abuse, but preserve
a controlled way to test L3 connectivity during incidents.

# Security Considerations

IPv6 restores global routability; **absence of NAT is not absence of need for
firewall policy**. ULAs and link-local addresses still require filtering at
boundaries. ICMPv6 filtering must preserve ND and PMTUD. Application-level
ACLs and security products must parse IPv6 literals correctly (see
(#application-readiness)).

**Security appliances and host security software are notoriously weak on IPv6**
--- incomplete decode, IPv4-only dashboards, agents that drop or mislabel v6
traffic, and policies that silently fail open or closed. Engage the **security
organization very early** in the IPv6 program, in parallel with out-of-band and
network design (see (#oob-management)). In many enterprises, application SREs
**do not have full visibility** into which tools the security team deploys;
there is often deliberate **operational secrecy** around EDR, NDR, DLP, and
forensics platforms. Assume unknown agents exist on every host until proven
otherwise (see (#host-agents)); establish a shared readiness process with
security leadership rather than discovering blockers during the first IPv6-only
pilot.

Security monitoring systems **MUST** receive IPv6 traffic mirrors, tap coverage,
and metadata **on parity with IPv4** before declaring IPv6 production-ready.
Validate that incident response playbooks (pcap collection, IP blocking,
geo blocking, threat intel feeds) work with **128-bit addresses** and canonical
text forms [@!RFC5952]. PR static analysis for IPv4-only patterns
(see (#static-analysis)) complements but does not replace security-tool
qualification.

Operator inventory practices in (#application-readiness) also reduce supply-chain
risk from undeclared IPv4-only dependencies in the control plane.

# IANA Considerations

This document has no IANA actions.

# Acknowledgments {#acknowledgments}

The authors thank the following people who contributed suggestions and
editorial improvements to this document:

* **Jason Healy** (Suffield Academy)

<reference anchor="ARCEP-IPV6-GUIDE" target="https://www.arcep.fr/fileadmin/cru-1648459125/reprise/observatoire/ipv6/guide-entreprises-how-to-deploy-IPv6-march-2022.pdf">
  <front>
    <title>How to Deploy IPv6 in Your Enterprise (Guide for Enterprises)</title>
    <author>
      <organization>ARCEP</organization>
    </author>
    <date year="2022" month="March"/>
  </front>
</reference>

<reference anchor="ARIN-APPS-V6" target="https://www.arin.net/resources/guide/ipv6/preparing_apps_for_v6.pdf">
  <front>
    <title>Preparing Applications for IPv6: A Software Developers Guide to Writing and Migrating Networked Applications for Use on IPv6 Networks</title>
    <author>
      <organization>ARIN</organization>
    </author>
  </front>
</reference>

{backmatter}
