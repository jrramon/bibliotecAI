# Hablar con la biblioteca — diseño para más adelante

Notas sueltas surgidas de una conversación filosófica el 1 de mayo de
2026. No es un plan ejecutable todavía: es la captura del cómo se va a
sentir el feature y de las restricciones técnicas que lo hacen posible
(o difícil). Lo dejamos aquí para no perderlo. Cuando lo abramos en su
propio Slice, se reordena en Plan ejecutable usando esto como base.

## El reencuadre

No es «mi biblioteca responde a mis consultas» — eso ya lo tenemos en
Telegram (Slices 5-7). Eso es mejor índice, mejor interfaz.

Es **conversar con los personajes y las historias**. Hablar con
Watanabe en lugar de hablar de *Tokio Blues*. Sentarse con Holden
después de cerrar el libro. Preguntarle a Genji qué hizo de su muerte.
La lectura siempre fue una conversación a medias — el autor habló, el
lector respondió internamente, el libro nunca pudo replicar. Esto
cierra el círculo.

## Lo que NO cambia, y por qué importa

- **El libro no se acuerda de la conversación**. El libro es texto
  fijo, siempre habla desde las mismas páginas. No persistimos
  «historial por libro».
- **El lector sí cambia**. Vuelves al libro en otro momento de tu vida
  y la conversación es otra — pero porque tú eres otro, no porque el
  libro evolucionara.
- **Por tanto: cero `BookConversation` por libro**. Cero estado
  acumulado entre vueltas. Cada vuelta empieza limpia, con el libro tal
  cual está escrito y con tu lector-de-hoy.
- (La memoria que sí persiste vive donde ya vive: en tus
  `UserBookNote`, tus `ReadingStatus`, tus comentarios. *Eso* es lo
  que evoluciona.)

## La restricción técnica honesta

Claude no sabe con fiabilidad qué libros tiene en su corpus. Tiene un
gradiente: conoce bien lo canónico, regular lo popular, vagamente lo
traducido, nada lo del long tail. Y peor — **no distingue desde dentro
entre «recuerdo el libro» y «tengo un resumen vívido del libro»**.
Confabula sin saber que confabula.

Implicación de diseño: **no podemos confiar en su memoria**. Tenemos
que inyectar el contexto del libro (sinopsis, fragmentos clave,
personajes, notas del lector) en el system prompt cada vez. Lo que
«sabe» pasa a ser explícito, no introspectivo.

Esto convierte cada llamada en RAG sobre el libro, no en «pregúntale a
Claude lo que sepa». Cambia la arquitectura.

## Slices candidatos (no plan, solo orden tentativo)

### Slice A — «Habla con este libro» mínimo
- Botón en `Book#show`. Abre un chat (modal o sub-página).
- System prompt incluye: título, autor, sinopsis, año, género, las
  `UserBookNote` del usuario, los `Comments` de los co-lectores.
- El bot habla *sobre* el libro, no *como* el libro. Estilo de
  bibliotecario informado.
- Sin persistencia de la conversación (el libro no recuerda).
- Verificable: si la sinopsis está vacía, lo dice; no inventa.

### Slice B — Modo personaje
- En la misma vista, selector de personaje.
- Lista de personajes: para empezar, manual al añadir el libro
  (campo `characters: text[]`). Después, Claude puede sugerir y el
  usuario confirma.
- System prompt: «Eres [personaje] de [libro] de [autor]. Habla como
  hablaría ese personaje. El lector ya ha leído el libro.»
- Aviso de honestidad embebido: si el libro está fuera del corpus
  conocido, el personaje declara que «su voz puede no ser exacta».

### Slice C — Conversación multi-libro
- El lector elige 2-3 libros de su biblioteca y habla con todos a la
  vez. «¿Qué pensaríais Watanabe y Naomi del consentimiento?»
- System prompt: contexto de los N libros + identidad de cada
  interlocutor.
- Útil también para recomendaciones: «de los que tengo, ¿qué leer
  después de Pedro Páramo?» con justificación cruzada.

### Slice D — Lector como contexto
- El system prompt incluye un perfil de lectura: qué ha leído (con
  fechas), qué está leyendo, qué dejó a medias, qué tiene en wishlist.
- Permite respuestas tipo «leíste *Cien años de soledad* hace 8 meses;
  esto te va a recordar a aquello». Conversación que **te conoce como
  lector**, no solo como base de datos.

### Slice E — Lector compartido
- En libros con varios miembros, el chat puede ver los comentarios y
  notas que CADA lector dejó (con permiso). «Habla con Tokio Blues
  sabiendo que Ana lo leyó como una novela sobre el duelo y tú lo
  estás leyendo como una novela sobre la juventud.»
- Esto es lo que convierte la biblioteca en interlocutor *compartido*
  y no solo *personal*. Es donde hace clic el «hablar con OUR library»
  en vez de «MY library».
- Cuidado de privacidad: las notas privadas son privadas. Los
  comentarios públicos sí entran.

## Cuts conscientes

- **Texto completo del libro**: no. Copyright + coste de tokens. Nos
  quedamos con sinopsis + notas + comentarios + (futuro) fragmentos
  curados manualmente por el lector.
- **Persistencia de conversaciones**: no. El libro no se acuerda; el
  reader sí, y vive en sus notas existentes.
- **Voz de audio**: no en el MVP. Texto.
- **Modo «autor»**: tentador («habla con Murakami») pero confunde la
  cosa. El autor es un personaje real con vida fuera de sus libros;
  encarnar a una persona viva con un LLM es un agujero negro ético.
  Hablar con personajes ficticios es radicalmente más limpio.

## Riesgos y por qué hay que ir con cuidado

- **Sustitución**: que la conversación con el libro reemplace la
  experiencia de leerlo. La línea entre «mi biblioteca me ayuda a
  recordar» y «mi biblioteca lee por mí» es muy fina. UX debe insistir
  en que la conversación es post-lectura, no pre.
- **Confabulación**: incluso con RAG, Claude rellena huecos
  plausiblemente. Hay que mostrar siempre las fuentes (qué fragmento /
  qué nota / qué sinopsis usó para responder). Inspiración:
  Perplexity citing.
- **Vigilancia disfrazada de relación**: «la biblioteca te dice cosas
  que no le has preguntado» suena bonito hasta que «hace 8 meses
  prometiste releer Pedro Páramo, ¿lo hiciste?» se siente intrusivo.
  Mantener la iniciativa siempre del lector.
- **Simulacro del simulacro**: el personaje al que «hablas» es la
  predicción de Claude sobre cómo hablaría ese personaje. Útil, pero
  no sagrado. Conviene que el bot lo recuerde explícitamente.

## Pregunta abierta para cuando lo retomemos

¿La conversación es **dentro de la ficha del libro** (intima,
contextual, una pestaña más del libro) o **fuera, en una sala aparte**
(estilo «sala de estar» donde invitas a varios libros)? Probablemente
las dos, con UX distinta. Pero la primera vez convendría empezar por
una sola — la de la ficha del libro — y dejar la sala de estar para
cuando los multi-libro pidan paso.
