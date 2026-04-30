# Security audit — Implementation Safety Skill

Audit of BibliotecAI against the 8 checklists in `.claude/SKILLS/security/SKILL.md`
(Implementation Safety, Rails). Date: 2026-04-22.

**TL;DR — ✅ Zero critical findings. Brakeman clean. App is safe to publish open-source.**

---

## 1. Nil Safety · ✅ PASS

Checked risky patterns across controllers, models, helpers. The app uses
`&.` consistently where needed:

- `avatar_for(user)` guards `user` and `user.avatar.attached?` with safe
  navigation (`app/helpers/avatars_helper.rb:10-11`).
- `previous_last_seen_at` falls back to `nil` on invalid ISO strings
  (`app/controllers/application_controller.rb:26-30`).
- `cover_photo_from_params` / `wishlist_item_from_params` use `find_by`
  (returning nil) and the caller checks with `&.completed?`
  (`app/controllers/books_controller.rb:179-198`).

No `.find_by(…).method` chains without nil guards.

---

## 2. ActiveRecord Safety · ✅ PASS (with one minor note)

- **Tenant isolation**: every `find`/`find_by` on library-scoped records
  goes through `current_user.libraries.friendly.find(…)` or
  `current_user.wishlist_items.find(…)`. A signed-in user can never
  `find` another user's library, book, comment, cover-photo, reading
  status, or wishlist item via URL tampering.
  - Checked: 14 occurrences across `books`, `comments`, `cover_photos`,
    `invitations`, `libraries`, `reading_statuses`, `shelf_photos`,
    `wishlist_items`, and `books#wishlist_item_from_params`.
- **Eager loading**: `Book.search_for_viewer` uses `.includes(:library)`,
  `UserBookNote.search_for_viewer` uses `.includes(book: :library)`.
  Library index renders `library.books.count` / `library.users.count`
  per card — this is an N+1 for large library counts. Noted for a
  future counter-cache if load grows (low priority — today's user has
  1–3 libraries per account).
- **Validation failures**: `if @book.save … else render … status:
  :unprocessable_entity end` pattern is used throughout — never silent.
- **Indexes on foreign keys**: confirmed via schema (every
  `t.references` generates an index by default in Rails 8).
- **Scopes over class methods**: `Book.scope :recent`, `.with_cdu`,
  `.with_genre`, `ReadingStatus.scope :active/:completed/:ordered`,
  `WishlistItem.scope :recent`.

**Minor note**: `Library#show` triggers `@library.books.count` +
`@library.users.count` + `@library.shelf_photos.count` — three
separate COUNT queries on every page render. Cheap individually but
could be a counter-cache someday.

---

## 3. Security · ✅ PASS

### SQL injection — ✅
- No string interpolation in `where(…)` calls. Grep for
  `where\(".*#\{` returns one match (`Book.with_cdu`) which interpolates
  **inside** the parameter binding (`?`), not the SQL string — safe.
- All search methods use `sanitize_sql_like(query.downcase)` to escape
  `%` and `_` wildcards before LIKE lookups.

### XSS — ✅
- `html_safe` is used only on literal empty strings
  (`"".html_safe`) in `AvatarsHelper` to satisfy the return type.
- `raw()` is not used anywhere in views.
- ActionText (used for comments) auto-sanitises rich body.
- User-supplied strings in ERB are HTML-escaped by default.

### Mass assignment — ✅
- Every controller uses strong parameters
  (`params.require(…).permit(…)` or the Rails 8
  `params.expect(model: […])` shorthand).
- No `Model.create(params[:x])` or `@record.update(params)` anywhere
  (grep returns no matches).
- `books#book_params` explicitly omits `:notes` — personal notes are
  per-user via `UserBookNote`, separately permitted at `#note`.

### Authentication — ✅
- Devise handles `has_secure_password` equivalent (database-
  authenticatable with bcrypt).
- `before_action :authenticate_user!` on every controller that touches
  user data. The only intentionally unauthenticated actions are
  `InvitationsController#show` (validates a token), Devise's own
  sign-in/sign-up, and `PublicWishlistsController#show` (validates a
  token).
- Password change: the custom
  `Users::RegistrationsController#update` requires `current_password`
  when and only when the user changes email or password
  (`password_change_requested? || email_change_requested?`).
  Profile-only updates (name, avatar) don't re-prompt.

### Sensitive data in logs — ✅
- `config/initializers/filter_parameter_logging.rb` filters:
  `:passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate,
  :otp, :ssn, :cvv, :cvc`.
- The filter catches `wishlist_share_token`, `reset_password_token`,
  `normalized_key_hash`, and all password fields.

### Authorisation — ✅
- `CommentsController#destroy` — `if @comment.user_id ==
  current_user.id` (only the author can delete).
- `InvitationsController#create` — `require_owner!` before_action
  (only the library owner can invite).
- `ReadingStatusesController#destroy` — scope
  `book.reading_statuses.where(user: current_user).find(params[:id])`
  (a user can only delete their own history entries).

### Public wishlist token — ✅
- `SecureRandom.urlsafe_base64(24)` → 192-bit entropy, not guessable.
- `User.find_by(wishlist_share_token: params[:token])` — route
  `get "/w/:token"` guarantees `params[:token]` is a non-empty
  string; there's no way to hit this action with `token: nil` to
  match users with `wishlist_share_token IS NULL`.
- Rotation (`regenerate_wishlist_share_token!`) generates a fresh
  token, invalidating the previous URL atomically. Disable sets it
  back to `nil`.
- Public page uses its own minimal layout (`layout "public"`) with
  `<meta name="robots" content="noindex,nofollow">` so shared links
  don't land in search engines.
- The public page shows `owner.display_name` only — never the email,
  never libraries, never other users' data.

---

## 4. Error Handling · ✅ PASS (acceptable tradeoffs)

6 bare `rescue => e` / `rescue => _` found. Each is intentional:

| Location | Rescued from | Behaviour |
|---|---|---|
| `book_cover_fetcher.rb:49` | image dimension sniff failure | returns `nil`, caller treats as unknown |
| `books_controller.rb:12` | `BookCoverFetcher.call` unexpected error | logs WARN, redirects with alert |
| `books_controller.rb:173` | `apply_candidate` (HTTP/JSON) | logs WARN, redirects with alert |
| `books_controller.rb:230` | `attach_cover_from_photo` | logs WARN, non-fatal |
| `book_identification_job.rb:69` | cover fetch inside a shelf-photo job | logs WARN, doesn't fail the main job |
| `book.rb:150` | `prune_matching_wishlist_items` after_create | logs WARN, book still saves |

All peripheral cleanup/enrichment paths. The main flows
(`Book#save`, `BookIdentificationJob`, `CoverIdentificationJob`) use
specific rescues (`ClaudeBookIdentifier::Error`, `Timeout::Error`,
`ActiveRecord::RecordNotFound`).

---

## 5. Performance · ✅ PASS

- `pluck(:genres)` used in tags rail (no `.map(&:genres)`).
- `exists?` used in template conditionals where applicable; none of
  the hot-path conditionals use `any?` on unloaded scopes.
- `find_each` not used because no batch jobs operate over large tables
  (claude-worker processes one record at a time).
- All FKs indexed (Rails 8 default).

---

## 6. Migration Safety · ✅ PASS

- `strong_migrations` gem in the Gemfile enforces rules at dev time.
- `add_index :wishlist_share_token, unique: true, algorithm:
  :concurrently` with `disable_ddl_transaction!` is the production-
  safe pattern.
- All `create_table` calls include `null: false` on required columns,
  defaults on enums (`status`, `role`, `state`), FK constraints on
  every `references`.
- No `remove_column` / `change_column` migrations that would need a
  two-step deploy.

---

## 7. Brakeman static analysis · ✅ CLEAN

```
Controllers: 14
Models: 13
Templates: 54
Errors: 0
Security Warnings: 0
```

Two services are explicitly skipped in `config/brakeman.yml`:
`ClaudeBookIdentifier` and `ClaudeCoverIdentifier`. Both call
`Open3.capture3(binary, arg1, arg2, …)` passing an **argv array**, not
a shell string. Kernel-level `exec()` does not invoke a shell in this
form, so even if `CLAUDE_BIN` or the image path contained shell
metacharacters, they would be treated as literal filename fragments
and the exec would fail — not execute arbitrary commands. Skipping
those two files is narrower than disabling the `CommandInjection`
check globally.

---

## 8. Observations for hardening (non-blocking)

Low-priority items noted during the audit. None block an open-source
release; these are "someday" improvements.

- **CSP** — `config/initializers/content_security_policy.rb` is left
  as the Rails default (commented scaffold). A production deployment
  should enable a real policy (`script-src :self`, `img-src` allowing
  Google Books thumbnails, `connect-src` for ActionCable). Filed as
  tech debt.
- **Counter caches** — the library index runs 3 COUNT queries per card
  on every dashboard hit. Fine today; a `books_count`/`users_count`
  column is the natural next step if the dashboard feels slow.
- **Bullet gem** — not installed. Current endpoints are fast enough
  that N+1s would be noticeable in tests, but adding Bullet in dev
  would catch regressions earlier.
- **Rate limiting** — no throttling on `/users/sign_in`, the public
  wishlist URL, or the ⌘K search. Rack::Attack is a one-file add.
  Not critical for a personal/family-sized deployment.

---

## Conclusion

BibliotecAI passes every hard check in the Implementation Safety skill
and Brakeman's static scan. No secrets live in the repo (neither
currently nor in history), tenant isolation is rigorous, user inputs
are validated and parameterised, auth is Devise-standard, and the
public share surface is minimal-by-design. Safe to publish.
