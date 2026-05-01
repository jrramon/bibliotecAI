# BibliotecAI 函

A small, Japanese-aesthetic library app for groups of readers. You can:

- Share one or more libraries with friends, family or a book club.
- Add books by hand, by photographing a shelf (Claude reads the spines), or
  by dropping a photo of a single cover (Claude fills the metadata).
- Track reading status per user — who's reading what, who has read it, who
  has dropped it — with a full history of re-reads.
- Keep private personal notes per book, per user.
- Keep a personal wishlist (separate from the library) with an optional
  public share link.
- Comment inside a book thread, search across your tenants with ⌘K, and
  switch between spine / grid / list layouts of the bookshelf.
- **Talk to your library from Telegram**: ask «¿qué tengo de Murakami?»,
  apunta libros en tu wishlist, gestiónala, y manda fotos de portadas
  para que aterricen como libros (o como deseos, si pones «wishlist» en
  el caption). Claude responde llamando a un servidor MCP local con
  herramientas acotadas a tu propio scope.

The spine-identification, cover-identification and Telegram-conversation
paths call the **Claude Code CLI** (`claude -p`) on the host, so a
subscription-authenticated Claude account works without extra API keys.

## Stack

- Ruby 3.3.6 / Rails 8.0.3
- PostgreSQL 16 / Puma
- Hotwire (Turbo + Stimulus), ActionText, ActiveStorage
- Propshaft + importmap-rails
- Solid Cache / Solid Queue / Solid Cable
- Devise, FriendlyId, SimpleForm, image_processing
- Docker Compose (dev)
- Minitest + Capybara + Selenium

## Prerequisites

- Docker + Docker Compose.
- Ruby 3.3.6 + Bundler on the host (only needed to run the claude-worker).
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) on the
  host, authenticated with your Anthropic account.
- Optional: a personal [Google Books API
  key](https://console.cloud.google.com/apis/credentials) — without one the
  shared per-IP quota (~1000 queries/day) is easily exhausted.

## Setup (local)

```bash
cp .env.development.example .env
# edit .env and set GOOGLE_BOOKS_API_KEY if you have one

docker compose build
docker compose up -d
docker compose exec web bin/rails db:prepare db:seed
```

Visit <http://localhost:3000>. Dev mail dashboard at
<http://localhost:3000/letter_opener>.

### Running the claude-worker on the host

Shelf- and cover-photo identification happens in a host process because the
Claude CLI is not available inside the Rails container. In another
terminal, from the project root:

```bash
bin/shelf-photo-poller
```

Environment variables (all optional):

- `CLAUDE_BIN` — absolute path to the Claude CLI (defaults to
  `$(which claude)`).
- `INTERVAL` — seconds between polls (defaults to 5).
- `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USERNAME`,
  `DATABASE_PASSWORD` — defaults match docker-compose (`localhost:5433`,
  `rails_dev` / `aqwe123`).

Check the queue state any time with `bin/queue-status` — it lists pending
shelf/cover photos, recent Telegram messages, and whether the worker is
alive.

### Telegram bot (optional)

The Telegram side is opt-in. Once enabled, every linked user can chat
with their own libraries from a private chat: list/add/remove wishlist
items, search the catalogue, and add books by photographing covers.

1. Talk to [`@BotFather`](https://t.me/BotFather) to create a bot. Note
   the token (`8691…:AAF…`) and the username (`MyBibliotecaiBot`).
2. Generate a webhook secret:
   `ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'`
3. Add three vars to `.env`:

   ```
   TELEGRAM_BOT_TOKEN=8691…
   TELEGRAM_BOT_USERNAME=MyBibliotecaiBot
   TELEGRAM_WEBHOOK_SECRET=<hex you just generated>
   ```

4. Restart the web container so the env reloads:
   `docker compose restart web`.
5. Expose your dev box over HTTPS — for example with
   `ngrok http 3000` — and register the webhook with Telegram:

   ```bash
   curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://<tunnel>/telegram/webhook/<SECRET>"
   ```

6. Restart the host worker (`bin/shelf-photo-poller`) so it sees the new
   env. The wrapper sources `.env` automatically.
7. From your profile in BibliotecAI (`/users/edit`) click "Conectar
   Telegram" → open the deep-link → start a chat with the bot. The
   profile page refreshes live (Turbo Stream) once the bind succeeds.

Then try: «¿qué bibliotecas tengo?», «apunta *Kokoro* en mi wishlist»,
«¿qué hay en mi wishlist?», «borra el último». Send a photo of a book
cover (no caption) to add it to your default library; add a caption
like «wishlist» or «para luego» to apunt it instead.

Full setup recipe and architecture in
[`docs/telegram-bot.md`](docs/telegram-bot.md).

### Storage

ActiveStorage uploads live in a named Docker volume (`app_storage`) so they
survive `docker compose down/up` and image rebuilds. Postgres data lives in
`pg_data` the same way. Back up with:

```bash
docker run --rm \
  -v bibliotecai_app_storage:/data \
  -v $PWD:/backup alpine \
  tar czf /backup/storage.tgz -C /data .
```

## Tests

```bash
docker compose exec web bin/rails test           # unit + mailer
docker compose exec web bin/rails test:system    # Capybara + headless Chrome
docker compose exec web bundle exec standardrb
docker compose exec web bundle exec erb_lint --lint-all
docker compose exec web bundle exec brakeman --no-pager -q
```

## Docs

- [`docs/flujo-foto-portada-libro.md`](docs/flujo-foto-portada-libro.md) —
  end-to-end flow of the cover-photo → Claude → add-book pipeline, with a
  per-phase debugging checklist.
- [`docs/telegram-bot.md`](docs/telegram-bot.md) — Telegram bot setup
  (BotFather, webhook, ngrok) and the MCP architecture behind it.
- [`CHANGELOG.md`](CHANGELOG.md) — what shipped, by slice.

## Contributing

Pull requests are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for
style, tests, and the slice-based workflow; [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
for expected behaviour; and [`SECURITY.md`](SECURITY.md) to report a
security issue privately.

## License

BibliotecAI is distributed under the [GNU Affero General Public License
v3.0](LICENSE) — derivative works, including network-hosted forks, must
make their source code available under the same license.
