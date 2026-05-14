# Plan: bibliotecas públicas read-only

## Context

Del backlog (`docs/backlog.md`): «Bibliotecas públicas / link de solo lectura: que el dueño pueda compartir una biblioteca con un link de invitado (sin login) para que sólo la vea. Análogo al `public_wishlists` ya existente».

Objetivo: que el owner de una biblioteca pueda activar/desactivar un link público (`/l/:token`) que cualquiera puede abrir sin login y ver los libros — sin notas privadas, sin reading status, sin acciones.

## Estado actual relevante

- **Patrón análogo `public_wishlists`** funciona ya, sirve de molde:
  - Ruta `get "/w/:token"` (`config/routes.rb:67`).
  - Token en `User#wishlist_share_token` con `SecureRandom.urlsafe_base64(24)` (`app/models/user.rb:19-30`).
  - `WishlistSharesController` para enable/rotate/disable (`config/routes.rb:66`).
  - Layout `app/views/layouts/public.html.erb` minimalista con `noindex,nofollow`.
- **Estado de Library hoy**:
  - `app/models/library.rb` solo tiene `name`, `description`, `owner`, `memberships`. NO hay token ni flag de público.
  - `LibrariesController` exige `authenticate_user!` y `current_user.libraries.friendly.find(...)`.
  - `app/views/libraries/settings.html.erb` ya existe y es donde encajará el nuevo panel "Compartir".
- **Partials de libro reutilizables**: `books/_spine`, `_card`, `_row` son agnósticos de `current_user` y se pueden usar en la vista pública sin tocarlos.

## Decisiones tomadas

- **Quién comparte**: solo el owner (no cualquier miembro). Coherente con el resto de configuración.
- **Qué se ve en público**: solo los libros (portada, título, autor, sinopsis, género, CDU). NO fotos de estantería, NO comentarios, NO recuento de lectores, NO miembros.
- **SEO**: `noindex,nofollow` por defecto (heredado del layout `public`). Sin opt-in para indexabilidad — si más adelante se quiere, se añade como mini-slice aparte.

## Cambios — partición en slices

Cada slice es independiente y commiteable por separado.

### Slice 1 — Backend del sharing (S)

- **Migration** `add_public_share_token_to_libraries`: añadir `libraries.public_share_token :string`, índice único, nullable.
- **`app/models/library.rb`**: métodos análogos a User's wishlist:
  - `public_shared?` → token presente.
  - `regenerate_public_share_token!` → asigna nuevo `SecureRandom.urlsafe_base64(24)`.
  - `disable_public_sharing!` → set token a nil.
- **Ruta + controller** para activar/rotar/desactivar:
  - `patch /libraries/:id/share` y `delete /libraries/:id/share` → `LibrarySharesController#update`/`#destroy`.
  - Autorización: solo el owner (no cualquier `membership`). Si no es owner → 404 silencioso.
- **UI**: panel "Compartir esta biblioteca" en `app/views/libraries/settings.html.erb`. Switch on/off + URL copiable (con un mini Stimulus reutilizando `clipboard_controller.js` existente) + botón "Regenerar token".
- **Tests del slice**: en el commit propio.

### Slice 2 — Vista pública (M)

- **Ruta**: `get /l/:token` → `public_libraries#show`, name `public_library`.
- **Controller** `app/controllers/public_libraries_controller.rb`:
  - Sin `authenticate_user!`. Layout `public`.
  - `Library.find_by!(public_share_token: params[:token])`. Si no existe → 404 con mensaje genérico (no revelar si existe la biblioteca).
  - Carga `@books = @library.books.recent`. Sin notas, sin reading_statuses.
- **Vista** `app/views/public_libraries/show.html.erb` — versión podada de `libraries/show.html.erb`:
  - Cabecera: nombre de la biblioteca + descripción (si tiene). Una línea sobria "Biblioteca compartida — solo lectura".
  - Los 3 layouts (lomos/grid/lista) renderizados a la vez, conmutados por CSS con `data-shelf-layout` (igual que la vista privada).
  - Reutilizar partials `books/_spine`, `_card`, `_row` tal cual.
  - SIN: header CTAs, stat-row, "Leyendo ahora", search/sort/chips (van en S3), footer "Volver a mis bibliotecas".

### Slice 3 — Búsqueda + filtros + switcher en la vista pública (S)

- Añadir a la vista pública: barra de búsqueda (solo título/sinopsis — NO notas), selector de orden (los mismos `recent` / `title` / `author` ya en `Book.ordered_by`), chips de género (reutilizar partial `libraries/_genre_chips` con un mini render-only override del `library_genre_chip_path` para que apunte a `public_library_path(@library.public_share_token, …)`).
- Toggle inline de layout: el mini controller `layout_switcher_controller` + el partial `libraries/_layout_switcher` ya funcionan sin user — persisten en localStorage.
- Reutiliza `Book.ordered_by` y `Book.search_in_library` (con `viewer: nil` → la búsqueda en notas se cae sola, perfecto).

### Slice 4 — Tests (S)

- **Model**: `LibraryTest` — generar/rotar/desactivar token, `public_shared?` refleja estado.
- **Request/system**:
  - Visitar `/l/:token-bueno` sin login → ve la biblioteca.
  - Visitar `/l/:token-roto` → 404.
  - Tras `disable_public_sharing!`, el link vuelve 404.
  - Owner activa sharing desde settings → URL copiable visible.
  - Un miembro no-owner NO puede ver el panel de sharing (o el botón está deshabilitado).
- Verificar que `current_user` no aparece en la vista pública (no se filtra el `<header>` autenticado).

## Archivos a tocar

- Nuevo: `db/migrate/YYYYMMDDHHMMSS_add_public_share_token_to_libraries.rb`
- `app/models/library.rb` — 3 métodos nuevos.
- Nuevo: `app/controllers/library_shares_controller.rb`
- Nuevo: `app/controllers/public_libraries_controller.rb`
- Nuevo: `app/views/public_libraries/show.html.erb`
- `app/views/libraries/settings.html.erb` — panel "Compartir".
- `config/routes.rb` — `patch/delete /libraries/:id/share`, `get /l/:token`.
- `app/views/libraries/_genre_chips.html.erb` — pequeña adaptación para reutilizar con un helper que admita ambos contextos (privado/público).
- `app/helpers/libraries_helper.rb` — quizás un helper polimórfico `genre_chip_path_for(...)`.
- Tests: `test/models/library_test.rb`, `test/system/library_sharing_test.rb` (existe — extender), nuevo `test/system/public_library_test.rb`.

## Verificación end-to-end

1. **Migración**: `docker compose exec web bin/rails db:migrate`. Confirmar columna y índice.
2. **Smoke**:
   - Login como owner, ir a `library settings`, activar sharing, copiar URL.
   - Abrir esa URL en una ventana de incógnito → ve libros sin login.
   - Desactivar desde settings → la misma URL ya devuelve 404.
3. **Tests**: `docker compose exec web bin/rails test test/models/library_test.rb test/system/public_library_test.rb test/system/library_sharing_test.rb`.

## Forma de trabajar

Slice a slice, un commit por slice, parar tras cada uno para confirmar. Sugerencia de orden:

1. **S1** — backend del sharing (sin la vista pública: hasta aquí, el token existe pero `/l/:token` no resuelve).
2. **S2** — vista pública mínima (ya se puede compartir un link funcional, sin búsqueda).
3. **S4** — tests del estado actual (cubre S1 y S2). Adelantarlo aquí porque S3 es polish y vale la pena cerrar la base con cobertura antes.
4. **S3** — polish: búsqueda/orden/chips/switcher en la vista pública.
