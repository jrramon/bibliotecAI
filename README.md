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

### Storage

ActiveStorage uploads live in a Docker named volume (`app_storage`) mounted at `/app/storage`, so they persist across `docker compose down/up` and survive image rebuilds. Postgres data lives in `pg_data` the same way. Inspect with `docker volume ls`; back up with:

```bash
docker run --rm \
  -v bibliotecai_app_storage:/data \
  -v $PWD:/backup alpine \
  tar czf /backup/storage.tgz -C /data .
```

### Running the poller on the host

Shelf photo identification calls the host-installed Claude CLI, which isn't available inside the Rails container. A simple polling loop on the host picks up `ShelfPhoto.pending` rows and processes each inline (no forking, no queue backend) — this sidesteps the pg-gem fork crash that kills Solid Queue on macOS arm64.

```bash
# On the host (requires Ruby 3.3.6 + bundle install)
bin/shelf-photo-poller
```

Environment variables (all optional):

- `CLAUDE_BIN` — absolute path to the Claude CLI binary (defaults to `$(which claude)`).
- `INTERVAL` — seconds between polls (defaults to 5).
- `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USERNAME`, `DATABASE_PASSWORD` — defaults match docker-compose (`localhost:5433`, `rails_dev` / `aqwe123`).

To check where a photo stands without opening the UI, run `bin/queue-status`.

## Tests

```bash
docker compose exec web bin/rails test test:system
docker compose exec web bundle exec standardrb
docker compose exec web bundle exec erb_lint --lint-all
docker compose exec web bundle exec brakeman --no-pager -q
```

## Troubleshooting fotos de portada

Guia de flujo y depuracion del proceso de identificacion de portadas al crear libros:

- [`docs/flujo-foto-portada-libro.md`](docs/flujo-foto-portada-libro.md)

## License

AGPL-3.0. See `LICENSE`.
