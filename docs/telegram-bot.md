# Bot de Telegram — setup

Esta guía cubre el setup de desarrollo paso a paso para que el bot responda
desde tu instancia local. Entrega progresiva por slices: este documento
crece a medida que añadimos funcionalidad. **Slice 1**: el bot responde
«Hola desde Biblio» a cualquier mensaje. Sin auth, sin DB, sin Claude.

## 1. Crear el bot en Telegram

1. En Telegram, abre [@BotFather](https://t.me/BotFather).
2. Manda `/newbot`.
3. Elige nombre (cualquier cosa) y `username` (debe acabar en `bot`, p.ej. `BibliotecAIDevBot`).
4. BotFather te da un token tipo `1234567890:AAFx-...`. Cópialo — es el `TELEGRAM_BOT_TOKEN`.

## 2. Generar el webhook secret

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

La salida (64 chars hex) es tu `TELEGRAM_WEBHOOK_SECRET`.

## 3. Añadir las tres variables a `.env`

En la raíz del proyecto (`.env` está gitignored, no se sube):

```
TELEGRAM_BOT_TOKEN=1234567890:AAFx-...
TELEGRAM_BOT_USERNAME=BibliotecAIDevBot
TELEGRAM_WEBHOOK_SECRET=<el hex de 64 chars>
```

Reinicia el contenedor para que `web` lea las nuevas variables:

```bash
docker compose up -d --force-recreate web
```

## 4. Exponer localhost por HTTPS con ngrok

Telegram requiere HTTPS. En desarrollo lo más simple es ngrok:

```bash
ngrok http 3000
```

Anota la URL `https://<algo>.ngrok-free.app` que te muestra. Cada vez que
arrancas ngrok te da una URL nueva (a no ser que pagues plan).

## 5. Registrar el webhook con Telegram

Sustituye `<TOKEN>`, `<NGROK_URL>` y `<SECRET>`:

```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=<NGROK_URL>/telegram/webhook/<SECRET>"
```

Respuesta esperada: `{"ok":true,"result":true,"description":"Webhook was set"}`.

Para verificar:

```bash
curl "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
```

## 6. Probar

En Telegram, busca tu bot por su `username` y mándale cualquier cosa.
Debería responder «Hola desde Biblio» en 1-2 segundos.

## Limpieza

Para borrar el webhook (vuelve a long-polling, útil si quieres testear el
bot vía otro método):

```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/deleteWebhook"
```

## Producción

**Usa un bot separado para producción.** Los bots de Telegram son
independientes: cada uno tiene su token, su webhook URL y su estado. Si
compartieras el bot de dev con prod, al arrancar el entorno local
empezarías a recibir los mensajes reales de los usuarios.

| Variable | Dev (`.env` gitignored) | Producción (env vars del hosting) |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | token del DevBot | token del BotProd |
| `TELEGRAM_BOT_USERNAME` | `BibliotecAIDevBot` | `BibliotecAIBot` |
| `TELEGRAM_WEBHOOK_SECRET` | hex generado para dev | hex distinto para prod |

Pasos en producción:

1. Crear un bot prod en BotFather (otro `username`).
2. Generar otro `WEBHOOK_SECRET` con `ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'`.
3. Configurar las tres variables en tu hosting (Fly secrets, Heroku
   config vars, Kamal env, etc.). **Nunca commitearlas.**
4. Registrar el webhook apuntando al dominio público:
   ```bash
   curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
     -d "url=https://<tu-dominio>/telegram/webhook/<PROD_SECRET>"
   ```
5. Probar mandando un mensaje al bot prod.

El webhook de prod solo se registra una vez. Persiste mientras esté
disponible la URL.

## Troubleshooting

| Síntoma | Probablemente | Cómo verificarlo |
|---|---|---|
| `getWebhookInfo` muestra `last_error_message` | Tu app devuelve no-200 o tarda >10s | `docker compose logs web` busca `/telegram/webhook` |
| Bot no contesta nada | El secret de la URL no coincide | El controller responde 404 silenciosamente; revisar `.env` y reiniciar `web` |
| `setWebhook` devuelve `Bad Request: HTTPS url must be provided` | URL ngrok mal copiada | Debe empezar por `https://` |
| El bot contesta a mensajes viejos | Backlog acumulado mientras estaba sin webhook | Manda `/start` o cualquier mensaje nuevo y el backlog se procesa |
