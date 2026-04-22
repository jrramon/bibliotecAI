# Flujo de foto de portada al crear libro

Guia de referencia para entender y depurar el flujo completo de identificacion de portada:

- Parte web (subida + UI reactiva)
- Proceso de generacion (worker host + Claude)
- Creacion final del `Book` con portada adjunta

---

## Esquema secuencial

```text
Usuario (UI)
  │
  │ 1) Click en "📷 Identificar desde foto"
  ▼
Stimulus cover_upload_controller
  │
  │ 2) Abre file picker y auto-submit del form de upload
  ▼
POST /libraries/:library_id/cover_photos
(CoverPhotosController#create)
  │
  │ 3) Crea CoverPhoto(status=pending, image adjunta en ActiveStorage)
  │ 4) Responde Turbo Stream: reemplaza #new-book-form por "analyzing"
  ▼
UI (partial cover_photos/_analyzing)
  │
  │ 5) Se suscribe a turbo_stream_from [cover_photo, :status]
  ▼
Host poller (bin/shelf-photo-poller -> bin/photo-worker.rb)
  │
  │ 6) Polling: detecta CoverPhoto.pending
  │ 7) Ejecuta CoverIdentificationJob.perform(id)
  ▼
CoverIdentificationJob
  │
  │ 8) status=processing + broadcast
  │ 9) ClaudeCoverIdentifier.call(cover_photo)
  ▼
ClaudeCoverIdentifier
  │
  │ 10) Descarga blob temporal a tmp/cover_photos
  │ 11) Ejecuta `claude -p ... --output-format json`
  │ 12) Parsea JSON de salida
  ▼
CoverIdentificationJob
  │
  │ 13a) exito: status=completed + claude_raw_response + broadcast
  │ 13b) error: status=failed + error_message + broadcast
  ▼
UI (reemplazo de #new-book-form)
  │
  │ 14a) completed -> books/_new_form (prefill de titulo/autor/etc)
  │ 14b) failed -> cover_photos/_identification_failed
  ▼
Usuario envia form de crear libro
  │
  ▼
BooksController#create
  │
  │ 15) Crea Book
  │ 16) Si viene book[cover_photo_id], copia imagen a book.cover_image
  ▼
Libro creado en biblioteca
```

---

## Checklist de debugging (por fases)

### 1) UI: trigger de subida

- Verifica que el boton "Identificar desde foto" dispare `cover-upload#pick`.
- Verifica que el input file ejecute `change->cover-upload#submit`.
- Si no abre el selector o no envia, revisar `app/javascript/controllers/cover_upload_controller.js`.

### 2) Request web y persistencia inicial

- Comprueba que el POST llegue a `CoverPhotosController#create`.
- Comprueba que se cree un `CoverPhoto` con `status: pending`.
- Si falla el guardado, revisar validaciones de content-type y presencia de imagen en `CoverPhoto`.
- Tipos soportados: `image/jpeg`, `image/png`, `image/webp`, `image/heic`.

### 3) Estado "Analizando..." y suscripcion Turbo

- Verifica que se renderice `cover_photos/_analyzing`.
- Verifica que exista `turbo_stream_from [cover_photo, :status]`.
- Si no hay cambios en pantalla tras esperar, sospecha de worker caido o broadcasts no emitidos.

### 4) Worker host (poller)

- Asegura que este arrancado: `bin/shelf-photo-poller`.
- Revisa que `claude` este disponible en host o `CLAUDE_BIN` configurado.
- Confirma credenciales DB del host (`DATABASE_HOST`, `DATABASE_PORT`, etc.).
- Si el worker no procesa, revisar lock/PID (`tmp/photo-worker.pid`) y logs de heartbeat/ticks.

### 5) Job y estados de procesamiento

- `CoverIdentificationJob` debe mover `pending -> processing -> completed|failed`.
- Si queda en `processing` mucho tiempo, revisar timeout/caida del proceso.
- Si queda en `failed`, inspeccionar `error_message`.
- El worker intenta recuperar estados `failed` y `processing` stale hacia `pending`.

### 6) Claude y parseo de salida

- `ClaudeCoverIdentifier` guarda temporalmente imagen en `tmp/cover_photos`.
- Ejecuta `claude -p` y espera JSON.
- Si el parseo falla: revisar stdout devuelto por Claude (formato no JSON / fences mal formadas).
- Si hay timeout: revisar conectividad/API/cuotas o aumentar timeout si fuese necesario.

### 7) Broadcast y reemplazo de formulario

- En exito, debe reemplazar `#new-book-form` con `books/_new_form` prefill.
- En fallo, debe reemplazar con `cover_photos/_identification_failed`.
- Si el estado en DB cambia pero UI no, revisar canal Turbo y target `new-book-form`.

### 8) Creacion de Book y adjunto de portada

- Al enviar form final, verificar que viaje `book[cover_photo_id]`.
- `BooksController#create` debe llamar `attach_cover_from_photo`.
- Confirmar que el nuevo `Book` tenga `cover_image.attached? == true`.
- Si el libro se crea sin portada, revisar lookup de `cover_photo_id` dentro de la misma library y blob descargable.

---

## Comandos utiles de verificacion

```bash
bin/shelf-photo-poller
bin/queue-status
```

Opcional para diagnostico rapido:

- Revisar `log/development.log` buscando `CoverIdentificationJob`, `ClaudeCoverIdentifier`, `CoverApply`.
- Verificar en consola rails el estado de las ultimas `CoverPhoto`.

