# Invitar a un usuario independiente (con su propio espacio de bibliotecas)

## Contexto / problema

El registro es **invite-only** y el gate es:

```ruby
# app/controllers/users/registrations_controller.rb#create
Invitation.pending.where(email: email).exists?
```

Es decir, **ya existe un sistema de invitaciones completo** (token, email, expiración, `resend!`, `accept!`) y el registro cuelga de él. Hoy una `Invitation` siempre apunta a una biblioteca (`library_id NOT NULL`) y al aceptarse mete al usuario como `:member` en la biblioteca de otro.

Para invitar a un **usuario independiente** no hace falta un segundo sistema (ni montar invitaciones sobre la waitlist). Basta con:

> Una invitación **sin biblioteca**. Al aceptarla, en vez de unirte como `:member` a la biblioteca de otro, te crea **tu propia** biblioteca como `:owner`.

## Decisión de modelado

- Reusar `Invitation`. Si `library_id` está presente → colaborador (`:member`, comportamiento actual). Si es `null` → invitación de cuenta → al aceptar crea la biblioteca propia del usuario (`:owner`).
- La **waitlist se queda igual**: una lista pasiva de emails. El admin la revisa y manda una invitación sin biblioteca a quien quiera. No se le añade token, ni `accepted_at`, ni mailer.
- El gate del registro (`Invitation.pending.where(email:)`) **no se toca**: ya deja entrar a cualquiera con invitación pendiente, tenga o no biblioteca.
- "Espacio propio" lo crea `accept!` solo en la rama sin biblioteca. El `Library after_create :create_owner_membership` ya existente da el rol `:owner`.

Funnel objetivo:

```
waitlist_request (email)  ──admin revisa──▶  Invitation.create!(email:, invited_by: admin, library: nil)
                                                        │ (email con token, pipeline actual)
                                                        ▼
                                       /invitations/:token  ──▶ registro (gate ya abierto)
                                                        │
                                                        ▼
                                       accept!  ──▶  user.owned_libraries.create!  (rol :owner)
```

## Slices

### Slice 1 — Invitación sin biblioteca + `accept!` bifurcado
*El corazón. Con esto el flujo completo ya funciona end-to-end creando la invitación por consola.*

- Migración: `library_id` de `invitations` pasa a **nullable**.
- `Invitation`:
  - `belongs_to :library, optional: true`
  - `accept!` bifurca:
    ```ruby
    def accept!(user)
      transaction do
        if library
          library.memberships.find_or_create_by!(user: user) { |m| m.role = :member }
        else
          user.owned_libraries.create!(
            name: "Biblioteca de #{user.name.presence || user.email.split('@').first}"
          )
        end
        update!(accepted_at: Time.current)
      end
    end
    ```
  - Revisar `claimable_by?` (no depende de library, OK) y la validación de unicidad `scope: :library_id` (con `library_id` null sigue siendo válida).
- `invitations_controller#show`: mensajes nil-safe cuando no hay biblioteca:
  - sin sesión → "Crea una cuenta con #{email} para empezar tu biblioteca."
  - tras aceptar (library nil) → redirigir a la biblioteca recién creada (`user.owned_libraries.last` o el retorno de `accept!`), no a `@invitation.library`.
- Verificación (consola + navegador):
  - `Invitation.create!(email: "nuevo@x.com", invited_by: admin, library: nil)`
  - abrir el link del token → registrarse → acaba en **su** biblioteca, rol `:owner`, `owned_libraries.one?`.
  - Regresión: una invitación a biblioteca normal sigue metiendo como `:member` sin biblioteca propia.

### Slice 2 — Mailer nil-safe
*Para que el email de la invitación sin biblioteca no mencione una biblioteca inexistente.*

- `InvitationsMailer.invite` / su plantilla: condicional para el caso `library.nil?`.
  - Con biblioteca: copy actual ("te han invitado a «X»").
  - Sin biblioteca: "te han invitado a BibliotecAI; crea tu cuenta y tu biblioteca".
- Verificación: previsualizar/enviar ambos casos y revisar el texto y el link.

### Slice 3 — Disparar la invitación independiente cómodamente (opcional)
*Mientras tanto se hace por consola; este slice solo es azúcar de UI.*

- Mínimo (ya disponible sin código): `Invitation.create!(email:, invited_by: current_admin, library: nil)` + `InvitationsMailer.invite(...).deliver_later`.
- UI posible: en el índice/gestión de waitlist, botón "Invitar como usuario" que crea la invitación sin biblioteca y envía el email. Requiere decidir quién es `invited_by` (el admin actual) y dónde vive esa pantalla.

## Notas / decisiones abiertas

- Unicidad: el índice parcial `(library_id, email) WHERE accepted_at IS NULL` trata los `library_id` NULL como distintos en Postgres, así que no bloquea dos invitaciones de cuenta pendientes al mismo email. Riesgo menor (flujo lo dispara el admin); si molesta, añadir guard a nivel de app.
- Solo las invitaciones **sin biblioteca** crean biblioteca propia. Los colaboradores invitados a una biblioteca ajena NO reciben biblioteca — solo `:member`. (Decidido con el usuario.)
- `invited_by` en la invitación de cuenta = el admin que la manda. Sigue siendo `NOT NULL`, sin cambios.
