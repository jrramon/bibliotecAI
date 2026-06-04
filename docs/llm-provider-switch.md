# Switch de provider LLM (Claude CLI ↔ API OpenAI-compatible)

Cada tarea que llama a un modelo puede ir, **por configuración**, contra:

- **`claude_cli`** (por defecto) — shell-out al binario `claude` (Claude Code), auth de suscripción / `ANTHROPIC_API_KEY`.
- **`openai_compatible`** — cualquier API estilo OpenAI (`/chat/completions`): NaN.builders, OpenRouter, un vLLM local… Corre in-process (net/http), sin binario.

Las 4 tareas:

| Tarea | Servicio | Input | Notas |
|---|---|---|---|
| `shelf` | `ClaudeBookIdentifier` | foto de estantería | visión |
| `cover` | `ClaudeCoverIdentifier` | foto de portada | visión |
| `classify` | `BookClassifier` | título + autor (texto) | back-fill de CDU/géneros |
| `telegram` | `Telegram::Agent` | mensaje | agente con tools (MCP) |

## Variables de entorno

```
# Provider por defecto y override por tarea (override gana):
LLM_PROVIDER=claude_cli                 # claude_cli | openai_compatible
LLM_PROVIDER_SHELF=...
LLM_PROVIDER_COVER=...
LLM_PROVIDER_CLASSIFY=...
LLM_PROVIDER_TELEGRAM=...

# Modelo por tarea (id del modelo):
LLM_MODEL_SHELF=claude-opus-4-8         # p.ej. visión Claude
LLM_MODEL_COVER=claude-opus-4-8
LLM_MODEL_CLASSIFY=deepseek-v4-flash
LLM_MODEL_TELEGRAM=qwen3.6              # debe soportar tool-calling

# API OpenAI-compatible (sólo si alguna tarea usa openai_compatible):
LLM_API_KEY=sk-...
LLM_API_BASE_URL=https://api.nan.builders/v1   # default; cámbialo para otro proveedor
LLM_API_MODEL=qwen3.6                   # modelo por defecto si una tarea va a la API sin LLM_MODEL_*

# Precios opcionales (USD por 1M tokens) para que el gasto de la API
# cuente en el budget / Langfuse. Vacío = $0 (correcto si es tarifa plana):
LLM_PRICES={"qwen3.6":{"input":0.30,"output":0.90}}
```

Resolución: `Llm::Config.resolve(task)` devuelve `[provider, model]`. Provider = `LLM_PROVIDER_<TASK>` || `LLM_PROVIDER` || `claude_cli`. Modelo = `LLM_MODEL_<TASK>` (o, si va a la API sin uno, `LLM_API_MODEL`).

## Detalles que conviene saber

- **Imágenes:** `claude_cli` recibe la imagen por **ruta** (`--add-dir`); `openai_compatible` la manda **inline en base64**. El prompt se ajusta solo (el `{{image_path}}` se sustituye por una nota cuando el provider es inline) — no hace falta tocar el prompt de Langfuse.
- **Telegram:** con `claude_cli` las tools van por el runtime MCP del CLI (HTTP a `/mcp`); con `openai_compatible` el bucle de tool-calling corre **in-process** ejecutando las mismas `Mcp::Tools::*` (misma telemetría `TOOL` en Langfuse). El modelo de la API **debe soportar tool-calling** (p.ej. `qwen3.6`, `deepseek-v4-flash`).
- **Coste/budget:** `ClaudeBudget` suma `total_cost_usd`. `claude_cli` lo trae del envelope del CLI; `openai_compatible` lo calcula con `LLM_PRICES` si está configurado, si no cuenta **$0** (correcto para una API de tarifa plana). El consumo de tokens siempre llega a Langfuse.
- **Eval:** `langfuse:eval:shelves:run MODELS="claude-opus-4-8,qwen3.6"` enruta cada modelo solo: los `claude-*` al CLI, el resto a la API (inferido por el prefijo). Útil para comparar calidad. Ver `project_run_shelf_eval`.

## Dónde corre cada cosa

- En dev, el **worker de host** (`bin/shelf-photo-poller`) procesa las colas y hace `source .env`, así que recoge esta config. Una tarea en `openai_compatible` corre in-process (net/http) y **no** necesita el binario `claude`.
- En prod, el `claude-worker` usa `env_file: .env.production`; añade ahí las `LLM_*` que quieras.

## Ejemplo: imágenes en Opus 4.8, Telegram en NaN/qwen

```
LLM_MODEL_SHELF=claude-opus-4-8
LLM_MODEL_COVER=claude-opus-4-8
LLM_PROVIDER_TELEGRAM=openai_compatible
LLM_MODEL_TELEGRAM=qwen3.6
LLM_API_KEY=sk-...
```
