# ── Mail authentication DNS for fitmate.me (IN-61) ───────────────────────────────────────────
#
# WHY shared/ AND NOT dev/: SPF, DKIM and DMARC are properties of the ZONE, not of an
# environment. fitmate.me has exactly one set. Putting them under dev/ would invite stg/ and
# prod/ to grow their own copies, and three units fighting over the same apex TXT record is a
# race whose loser silently disappears.
#
# WHAT THIS FIXES: fitmate.me today has DMARC p=quarantine and NOTHING for it to pass —
# measured 2026-11-06, `dig TXT fitmate.me` returns ZERO records: no SPF, no DKIM. Any mail we
# send would fail both checks and be quarantined by the receiver, and we would blame the
# provider. The existing DMARC record is a REGISTRAR DEFAULT (its rua points at
# onsecureserver.net, an address we do not own, so no report has ever reached us).

terraform {
  source = "../../../../../devops-terraform-modules//cloud/cloudflare-dns"
}

# Cloudflare-only stack — deliberately does NOT include root.hcl, and generates its own scoped
# provider set, exactly as dev/cloudflare-tunnel does (see its comment at line 22).
#
# 🔴 TWO REASONS, BOTH LEARNED THE HARD WAY ON 2026-11-07:
#
# 1. root.hcl's generated providers need a REACHABLE CLUSTER. This unit touches nothing but
#    Cloudflare, and the cluster is frequently down; including root made this unit fail for a
#    reason unrelated to DNS.
# 2. Without a generated versions.tf, Terraform guesses the provider namespace and fails with
#      "provider registry does not have a provider named
#       registry.terraform.io/hashicorp/cloudflare ... Did you intend to use cloudflare/cloudflare?"
#    The MODULE declares no required_providers — that is this repo's convention, and it is the
#    UNIT's job to generate them.
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.11.2, < 2.0.0"
      required_providers {
        cloudflare = {
          source  = "cloudflare/cloudflare"
          version = "~> 5.23"
        }
      }
    }
  EOF
}

# Read straight from the environment rather than from an env.hcl local: shared/env.hcl has no
# cloudflare_api_token (only dev/env.hcl does), and dev/env.hcl itself resolves it with exactly
# this get_env call — so this is the same value from the same source, not a second mechanism.
generate "provider_cloudflare" {
  path      = "provider-cloudflare.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "cloudflare" {
      api_token = "${get_env("CLOUDFLARE_API_TOKEN", "")}"
    }
  EOF
}

locals {
  # Same zone as the tunnels — on-prem/fitmate/dev/cloudflare-tunnel/terragrunt.hcl:7
  zone_id = "71113800c684f8e9bd342c4545f9aecd"
}

inputs = {
  zone_id = local.zone_id

  records = [
    # ── Domain ownership ──────────────────────────────────────────────────────────────────
    {
      name    = "@"
      type    = "TXT"
      content = "brevo-code:52775e8a7bcdfefdfd7bd7be83ef012e"
      comment = "IN-61 Brevo domain ownership proof"
    },

    # ── SPF ───────────────────────────────────────────────────────────────────────────────
    #
    # -all is a HARD FAIL: receivers are told to reject anything not from these servers.
    # That is safe here ONLY because it was verified that nothing else sends as @fitmate.me —
    # measured 2026-11-06: no MX records, no DKIM selectors for google/zoho/s1/selector1, and
    # zero existing TXT records on the apex. If any of those had been present, this would have
    # to be ~all (soft fail) and this comment would say so.
    #
    # One include only. SPF has a hard limit of 10 DNS lookups and silently PERMERRORs past it;
    # every future sender added here spends part of that budget.
    {
      name    = "@"
      type    = "TXT"
      content = "v=spf1 include:spf.brevo.com -all"
      comment = "IN-61 SPF — Brevo only; -all safe, no other sender exists"
    },

    # ── DKIM ──────────────────────────────────────────────────────────────────────────────
    #
    # CNAMEs, not TXT — Brevo hosts the keys and rotates them, so we never touch these again.
    # (An earlier plan of mine assumed a single DKIM TXT record. Brevo issues TWO CNAMEs.)
    #
    # 🔴 proxied MUST stay false. The module defaults it false and validates it, but stating it
    # here too: Cloudflare's proxy rewrites CNAME answers, DKIM lookups then fail, mail still
    # sends, and the ONLY symptom is quietly landing in spam.
    {
      name    = "brevo1._domainkey"
      type    = "CNAME"
      content = "b1.fitmate-me.dkim.brevo.com"
      proxied = false
      comment = "IN-61 Brevo DKIM key 1"
    },
    {
      name    = "brevo2._domainkey"
      type    = "CNAME"
      content = "b2.fitmate-me.dkim.brevo.com"
      proxied = false
      comment = "IN-61 Brevo DKIM key 2"
    },

    # ── DMARC ─────────────────────────────────────────────────────────────────────────────
    #
    # 🔴 THIS REPLACES THE REGISTRAR'S RECORD, AND IT IS DELIBERATELY STRICTER THAN BREVO ASKED.
    #
    # Brevo's setup page suggests `p=none` with rua pointing at dmarc.brevo.com. p=none means
    # "do nothing when a message fails" — monitor only. It is the right default for a stranger
    # whose domain might already have legitimate senders they forgot about. It is the WRONG
    # default for us: we verified there are none, so quarantine costs us nothing, and p=none
    # would let anyone spoof noreply@fitmate.me with receivers told to allow it.
    #
    # Keeping p=quarantine (as today) and changing ONLY the reporting address, so the reports
    # arrive somewhere we can read instead of the registrar's onsecureserver.net.
    #
    # NOT p=reject yet: reject is the correct end state, but it should follow a period of
    # reading aggregate reports and confirming nothing legitimate is failing. Tightening before
    # we have ever read a single report would be guessing.
    {
      name    = "_dmarc"
      type    = "TXT"
      content = "v=DMARC1; p=quarantine; adkim=r; aspf=r; rua=mailto:dmarc@fitmate.me; fo=1"
      comment = "IN-61 DMARC — replaces registrar default; quarantine kept, reporting ours"
    },
  ]
}
