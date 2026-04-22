# Contributing to BibliotecAI

Thanks for wanting to help. This is a small, opinionated project — here is
what you need to know before sending a change.

## Local setup

The full walkthrough lives in [README.md](README.md). In short:

```bash
cp .env.development.example .env             # or .env.development — see README
docker compose up -d
docker compose exec web bin/rails db:prepare
```

The image-identification path (`bin/shelf-photo-poller`) runs **on the host**
because the Claude Code CLI is not available inside the container. See
[`docs/flujo-foto-portada-libro.md`](docs/flujo-foto-portada-libro.md) for
the full flow and where to look when something breaks.

## Running the tests

```bash
docker compose exec web bin/rails test         # unit + mailer + model
docker compose exec web bin/rails test:system  # Capybara + headless Chrome
```

Before opening a pull request:

- Add or update a test covering the change.
- Run `docker compose exec web bundle exec standardrb` and
  `docker compose exec web bundle exec erb_lint --lint-all`.
- Keep commits focused. A PR with one logical change is easier to review than
  a PR with five.

## Style

- **Ruby**: [standardrb](https://github.com/standardrb/standard) (no config,
  just run it). `bin/bundle exec standardrb --fix` handles the boring bits.
- **ERB**: [erb_lint](https://github.com/Shopify/erb_lint) with the default
  rule set.
- **CSS**: one big `application.css` for now. Keep variables in
  `:root { … }` at the top; section comments (`==== TITLE ====`) separate
  domains.
- **JavaScript**: Stimulus controllers only. No npm build step — import
  maps only.

## Slices and the plan

Features land as "slices" — small, self-contained increments with a goal,
affected files, and a test plan. If you open a PR that grows a new surface,
write a one-paragraph brief of the slice in the PR description: why, what
changed, how to verify.

## Commits and PRs

- Conventional-ish subjects: `feat:`, `fix:`, `refactor:`, `test:`, `chore:`,
  `style:`, `docs:`. Lowercase, imperative.
- Include a short body when the "why" isn't obvious from the diff.
- Update [CHANGELOG.md](CHANGELOG.md) under `## Unreleased`.
- Reference issues by number when applicable.

## License

BibliotecAI is licensed under [AGPL-3.0](LICENSE). By contributing you agree
to license your contribution under the same terms.
