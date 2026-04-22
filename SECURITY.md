# Security Policy

## Reporting a Vulnerability

If you find a security issue in BibliotecAI, please **do not open a public
GitHub issue**. Instead, send the details privately to the maintainers by
opening a [GitHub Security Advisory][advisory] on this repository
(Security tab → "Report a vulnerability").

When possible, include:

- A description of the vulnerability and why it matters.
- Steps to reproduce (or a minimal proof of concept).
- The versions / commit hash you tested against.
- Whether it affects any deployed instance you know of.

You can expect an initial acknowledgement within 7 days. We'll work with you
on a disclosure timeline that balances protecting existing deployments with
crediting your work.

## Scope

This project is distributed as-is under AGPL-3.0 (see [LICENSE](LICENSE)).
There is no "official" hosted instance to bug-bounty against — reports
concern the source code and the reference Docker setup only.

## Secrets hygiene

Anyone running this app locally or in production is responsible for their
own secrets:

- `config/master.key` — gitignored; regenerate with `bin/rails credentials:edit`
  if you don't have it.
- `.env` — gitignored; copy `.env.development.example` as a template.
- `GOOGLE_BOOKS_API_KEY` — optional, bring your own. Without one the public
  per-IP quota (~1000 queries/day) is shared.
- Database password — the default `aqwe123` in `docker-compose.yml` is for
  local development only; change it before any network-reachable deploy.

[advisory]: https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability
