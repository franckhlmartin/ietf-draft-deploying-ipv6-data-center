# Changelog

Significant content changes to `draft-martin-deploying-ipv6-data-center.md` are
recorded here. Formatting-only edits are omitted unless they affect published
semantics.

## Unreleased

- **Document structure (major):** Reorganize after §2 into a dual-track layout —
  **Part I** (§4 transition, §5 observability) and **Part II** (§7 OOB through
  §14 diagnostics, bottom-up). Rewrite §1.3 with rationale and role-based
  reading paths; update Abstract. No substantive content removed.
- **Acknowledgments (§17):** List document contributors (Jason Healy).
- **Introduction (§1):** Correct SRE expansion to Site Reliability Engineers.
- **Static addressing (§8.2):** Disable RA on switch ports and SLAAC on hosts
  (two layers of protection).
- **Build:** Drop `stream = "IETF"` for individual Datatracker submission; strip
  default `submissionType="IETF"` in `fix-mmark-xml.py` (fixes idnits
  SUBMISSION_TYPE_UNEXPECTED).
- **Introduction (§1):** Remove v6ops charter paragraph; expand Related Guides
  with RFC 7381 and RFC 4038.
- **Name resolution (§12):** Hostname connect retry across A/AAAA; Happy
  Eyeballs IPv4 delay; runtime-specific resolution (Java, non-glibc).
- **Addressing (§8):** `fe80::1` gateway as good practice; prefix allocation
  (/72 in closed DCs, NAT tracing); internal prefix routing filter; semantic
  prefix coloring in monitoring UIs.
- **Application readiness (§11):** Developer dual-stack/IPv6-only test
  environments; AI coding agent IPv6 skills in CI.
- **Network diagnostics (§14):** Reverse DNS and controlled ICMP echo inside
  the fabric.
- **ICMPv6 (§10):** World IPv6 Day/Launch PMTUD anecdote replaces LinkedIn
  example.
- **Observability (§5):** Dual-stack regression monitoring; treat IPv6 failures
  as hard failures.
- **Out-of-band (§7):** IPMI over IPv6 for remote reboot and provisioning.
- **Transition (§4):** Cultural shift and jump hosts before emergencies.
- **Internal vs external scope (§8.5):** IPv6-only on internal interfaces;
  dual-stack external edges; dual-homed edge servers for administration.
