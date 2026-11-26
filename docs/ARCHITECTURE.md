# UnRot architecture

UnRot is a Flutter app (`app/`) organised in three layers. Lower layers never import higher ones:

```
 ui/        Screens, reel widgets, pen canvas          (Flutter widgets, material_ui)
   │
 modules/   Feature engines                             (pure Dart + ChangeNotifier)
   │        ingestion · ai · generation · reels · visuals · study · feed
   │
 core/      Models, storage, utilities                   (pure Dart)
```

`app/lib/app/app_services.dart` is the **composition root**. It creates every repository and service and wires
them together. Swap an implementation there (e.g. a keychain-backed secret store) and the rest of the app is
unchanged.

## Data flow

```
 file / pasted text
        │  modules/ingestion  (runs in a background isolate)
        ▼
 TextExtractor ──► text with "# headings" + [[img:…]] figure markers ──► Chunker ──► SourceChunk[] + figure files
                                                                     │
               ┌─────────────────────────────────────────────────────┘
               ▼
 FeedEngine ── picks a source (feed shares) ──► StudyMode.nextChunk() ──► GenerationJob
     │                                                                        │
     │  re-uses unseen cached reels / mixes in due reviews (SRS)              ▼
     │                                              ReelGenerator (AI provider or offline)
     │                                                  PromptBuilder → AiProvider → ReelParser
     ▼                                                                        │
 FeedItem[] ──► FeedScreen (vertical PageView) ──► ReelWidgets.body(type) ◄───┘   (ReelRepository)
                     │
                     └─ interactions ──► ProgressTracker ──► ChunkProgress / ReelState (SM-2)  (ProgressRepository)
```

## Modules

| Module | Key files | Responsibility |
|---|---|---|
| `core/models` | `source.dart`, `chunk.dart`, `reel.dart`, `progress.dart`, `settings.dart`, `annotation.dart` | Plain data classes with tolerant JSON (de)serialisation. |
| `core/storage` | `json_store.dart`, `repositories.dart`, `settings_repository.dart`, `secret_store.dart` | Atomic, debounced JSON files; repositories are `ChangeNotifier`s the UI listens to. |
| `modules/ingestion` | `text_extractor.dart`, `extractors/*`, `chunker.dart`, `ingestion_service.dart` | File → text → sections. Pure-Dart PDF parser (xref/object streams, Flate, ToUnicode CMaps, font-size based heading detection, header/footer removal), EPUB, DOCX, HTML, Markdown, TXT. Optional `pdftotext` fallback on desktop. |
| `modules/ai` | `ai_provider.dart`, `providers/*`, `provider_registry.dart` | Bring-your-own-key providers: Anthropic (Messages API, structured outputs), OpenAI (Chat Completions), Google Gemini, any OpenAI-compatible server (OpenRouter, Ollama, LM Studio, Groq, Mistral, …). |
| `modules/reels` | `reel_types.dart` | Reel type registry: prompt format, JSON schema and validation per type. |
| `modules/visuals` | `expression.dart`, `visual_spec.dart` | Safe math expression language (parser + evaluator, no code execution) and the validated description of interactive visuals: function plots, charts, SVG diagrams (with `{{expression}}` templates), equations with steps, figures; controls, animations and goals. |
| `modules/generation` | `prompt_builder.dart`, `reel_parser.dart`, `ai_reel_generator.dart`, `offline_generator.dart`, `generation_service.dart` | Builds prompts from the section, study mode, learner progress and settings, then parses messy model output. Includes a key-less heuristic generator. |
| `modules/study` | `study_mode.dart`, `modes/builtin_modes.dart`, `progress_tracker.dart` | Study strategies (linear course, exam prep, rote memorisation, explore) plus mastery tracking and SM-2 spaced repetition. |
| `modules/feed` | `feed_engine.dart` | Composes the endless feed: source shares, reviews, caching, prefetching, focus mode, "explain more". |
| `ui` | `screens/*`, `reels/*`, `visuals/*`, `pen/pen_canvas.dart` | Feed (TikTok-style), library, source detail, progress, settings; interactive reel widgets; plot/chart painters, flicker-free live SVG, LaTeX rendering (`flutter_math_fork`), sliders/dials/toggles/buttons/steppers; pressure-sensitive pen canvas. |

## Extension points

Each extension below is an interface plus a registry.

### Add an AI provider

1. Implement `AiProvider` (usually by extending `HttpAiProvider`) in `modules/ai/providers/`:
   `complete(AiRequest, ProviderConfig, apiKey)` and `listModels(...)`.
2. Add it to `ProviderRegistry`. The settings screen picks it up automatically (fields for API key, model,
   base URL and any `ProviderOption`s you declare).
3. Add a test with `package:http/testing.dart`'s `MockClient` (see `test/providers_test.dart`).

### Add a reel type

1. Implement `ReelTypeSpec` in `modules/reels/reel_types.dart` (id, prompt format, JSON schema, `normalize`) and
   add it to `ReelTypes.all`.
2. Add a widget and register it in `ReelWidgets.builders` (`ui/reels/reel_widgets.dart`). Use `ReelContext.onAnswer`
   for objective answers and `onRate` for self-assessment, so progress and spaced repetition work automatically.
3. Optionally add it to study modes' `defaultReelMix` and to the offline generator.

### Add a visual kind or control

1. Accept and validate it in `VisualNormalizer.normalize` (`modules/visuals/visual_spec.dart`), add accessors to
   `VisualSpec` and describe it in `VisualReelSpec.promptFormat` (`modules/reels/reel_types.dart`).
2. Render it in `_VisualReelState._visual()` (`ui/reels/visual_reel.dart`) or, for a control, in `ParamControl`
   (`ui/visuals/controls.dart`). Parameters are a plain `Map<String, double>`; use `Expression.eval` for anything
   the AI writes as a formula.

### Add a study mode

Implement `StudyMode` (`nextChunk`, `isComplete`, `defaultReelMix`, `promptGuidance`, optional `reviewBoost`/
`teachFirst`/`mixFor`) and add it to `builtinStudyModes()`. It appears in the source detail screen.

### Add an import format

Implement `TextExtractor` (pure Dart, no Flutter imports, because it runs in an isolate) and register it in
`defaultExtractorRegistry()`. Emit Markdown headings (`#`, `##`) so the chunker can build sections.

### Swap storage or secrets

`JsonStore` is deliberately small. Repositories only use `read`, `write`, `scheduleWrite`, `delete` and `flush`,
so a SQLite/Drift or sync backend can replace it. `SecretStore` can be backed by libsecret, Keychain, Windows
Credential Manager or Android Keystore (e.g. via `flutter_secure_storage`).

## Persistence format

All files live in the app support directory (override with `UNROT_DATA_DIR`):

```
settings.json            AppSettings (no secrets)
secrets.json             API keys (0600 on Linux/macOS)
library.json             sources + per-source study settings
chunks/<sourceId>.json   sections of a source
reels/<sourceId>.json    generated reels (re-used for reviews)
images/<sourceId>/       figures extracted from the source (img1.jpg, img2.png, …)
progress.json            chunk mastery, reel SRS state, daily stats
annotations.json         pen strokes per reel (normalised 0..1 coordinates)
```

## AI request details

* One request generates a batch of reels (default 5) for one section. The prompt contains the study mode's
  goal, difficulty (adaptive from mastery and "too easy"/"confusing" feedback), recently missed questions,
  topics marked as confusing, summaries of existing reels (to avoid repeats), the learner's focus note, custom
  instructions and the section text.
* Anthropic: `POST /v1/messages` with `anthropic-version: 2026-10-21`, structured output via
  `output_config.format` (JSON schema of the requested reel types), optional `output_config.effort`, and
  server-side refusal fallbacks (`fallbacks: "default"`) on models that support them. A `400` is retried once
  without these extras.
* Requests that include `visual` reels are sent without a strict schema (visuals are free-form); JSON mode is
  still requested. The prompt lists the figures of the section (`img3: Figure 2 …`) so the AI can show them.
* The reel language is per source (`SourceStudySettings.reelLanguage`: app default, same as the source, or a
  language). Reels remember their language so cached reels in another language are not re-used.
* OpenAI / compatible: `POST /chat/completions` with JSON mode. Gemini: `generateContent` with
  `responseMimeType: application/json`.
* `ReelParser` tolerates code fences, prose around the JSON, type aliases and truncated output (complete objects
  are salvaged), and repairs LaTeX whose backslashes broke the JSON (`\sqrt`, `\frac` → `\\sqrt`, `\\frac`).
  Every reel is validated by its `ReelTypeSpec.normalize`; visuals get sliders added for any free variable the AI
  forgot to declare, SVGs are sanitised (no scripts, event handlers or external links).
* If a request fails, the feed falls back to the offline generator (configurable).

## Figures

Extractors turn images into figure markers in the text (`[[img:img3|Figure 2: …]]`) and return the image bytes:
EPUB `<img>`/SVG `<image>`, DOCX drawings (`a:blip` + relationships), PDF image XObjects (JPEG copied as is,
8-bit RGB/grey bitmaps re-encoded as PNG; images repeated on many pages, such as logos, are dropped; a following
"Figure n: …" line becomes the caption). The chunker keeps markers as separate blocks, `attachImages` links them to
sections, and `LibraryRepository` stores the files. Visual reels reference figures by id and the UI resolves them
with `AppServices.sourceImage`.

## Pen input

`PenCanvas` uses raw `Listener` pointer events, so it works the same on all platforms:
`PointerDeviceKind.stylus` draws with pressure, `invertedStylus` (eraser end) or the barrel button erases.
In "stylus only" mode touch and mouse never draw (palm rejection). When drawing with finger or mouse, the canvas
claims vertical drags so the feed does not scroll. On reels, a stylus can annotate directly, because the feed's
`ScrollBehavior` excludes the stylus from drag-to-scroll. Short stylus taps are ignored so buttons underneath
remain usable.
