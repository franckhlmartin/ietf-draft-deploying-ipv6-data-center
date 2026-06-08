# Changelog

Significant content changes to `draft-martin-deploying-ipv6-data-center.md` are
recorded here. Formatting-only edits are omitted unless they affect published
semantics.

## Unreleased

- **Acknowledgments (§15, new):** List document contributors (Jason Healy).
- **Introduction (§1):** Correct SRE expansion to Site Reliability Engineers.
- **Static addressing (§4.2):** Disable RA on switch ports and SLAAC on hosts
  (two layers of protection).
- **Build:** Drop `stream = "IETF"` for individual Datatracker submission; strip
  default `submissionType="IETF"` in `fix-mmark-xml.py` (fixes idnits
  SUBMISSION_TYPE_UNEXPECTED).
- **Introduction (§1):** Remove v6ops charter paragraph; expand Related Guides
  with RFC 7381 and RFC 4038.
- **Name resolution (§3):** Hostname connect retry across A/AAAA; Happy
  Eyeballs IPv4 delay; runtime-specific resolution (Java, non-glibc).
- **Addressing (§4):** `fe80::1` gateway as good practice; prefix allocation
  (/72 in closed DCs, NAT tracing); internal prefix routing filter; semantic
  prefix coloring in monitoring UIs.
- **Application readiness (§5):** Developer dual-stack/IPv6-only test
  environments; AI coding agent IPv6 skills in CI.
- **Network diagnostics (§8, new):** Reverse DNS and controlled ICMP echo inside
  the fabric.
- **ICMPv6 (§7):** World IPv6 Day/Launch PMTUD anecdote replaces LinkedIn
  example.
- **Observability (§10):** Dual-stack regression monitoring; treat IPv6 failures
  as hard failures.
- **Out-of-band (§11):** IPMI over IPv6 for remote reboot and provisioning.
- **Transition (§12):** Cultural shift and jump hosts before emergencies.
- **Internal vs external scope (§4.5):** IPv6-only on internal interfaces;
  dual-stack external edges; dual-homed edge servers for administration.
