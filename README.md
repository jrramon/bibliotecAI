# BibliotecAI

Shared book library app where members can add books manually or by uploading a shelf photo. An image-identification pipeline calls Claude Code CLI (`claude -p`) to extract titles + authors from the photo and returns an annotated image marking the spines it could not read.

## Stack

- Ruby 3.3.6 / Rails 8.0.3
- PostgreSQL 16 / Puma
- Hotwire (Turbo + Stimulus), ActionText, ActiveStorage
- Propshaft + importmap-rails
- Solid Cache / Solid Queue / Solid Cable
- Devise, FriendlyId, SimpleForm, image_processing
- Docker Compose (dev)
- Minitest + Capybara + Selenium

## Setup (local)

```bash
cp .env.development.example .env.development
docker compose build
docker compose up -d
docker compose exec web bin/rails db:prepare db:seed
```

Visit http://localhost:3000. Dev mail dashboard at http://localhost:3000/letter_opener.

### Running the worker on the host

The shelf-photo identification job calls `claude -p`, which is not available inside the Rails container. Run Solid Queue from the host:

```bash
# On the host (requires Ruby 3.3.6 + bundle)
bundle install
OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
  DATABASE_HOST=localhost DATABASE_PORT=5433 \
  DATABASE_USERNAME=rails_dev DATABASE_PASSWORD=aqwe123 \
  CLAUDE_BIN=$(which claude) \
  bin/rails solid_queue:start
```

If `claude` is not on `$PATH`, set `CLAUDE_BIN` to the absolute path (e.g. `/Applications/cmux.app/Contents/Resources/bin/claude`).

`OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` is required on macOS arm64 to keep the `pg` gem from segfaulting when Solid Queue forks worker processes.

## Tests

```bash
docker compose exec web bin/rails test test:system
docker compose exec web bundle exec standardrb
docker compose exec web bundle exec erb_lint --lint-all
docker compose exec web bundle exec brakeman --no-pager -q
```

## License

AGPL-3.0. See `LICENSE`.
