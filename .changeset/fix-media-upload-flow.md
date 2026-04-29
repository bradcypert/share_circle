---
"share_circle": patch
---

Fix media upload flow and add upload previews

- **Root cause fix**: Phoenix LiveView file inputs must be inside a `<form phx-change="...">` — without it `pushInput` never fires, `@uploads.media.entries` stays empty server-side, and `consume_uploaded_entries` always returns `[]`. Wrapped the post composer in `<form phx-submit="create_post" phx-change="validate_media">`.
- **Add `auto_upload: true`**: Uploads begin the moment a file is selected so the XHR is done before the user clicks Share. LiveView's phx-submit gate also blocks submission until all uploads complete.
- **Upload previews**: `<.live_img_preview>` for images (absolute inset-0 to fill the aspect-ratio container), film-icon + filename for video files.
- **Log complete_upload failures**: Server-side errors now emit `Logger.error` instead of being silently swallowed.
- **Fix Ecto 3.13 `nil` comparison crashes** (6 call sites): `Repo.get_by/3` raises `ArgumentError` when any keyword value is `nil` in Ecto 3.13+. Fixed every occurrence across `media.ex`, `posts.ex`, `chat.ex`, `notifications.ex`, and `conversation_channel.ex` — replacing them with `Repo.get` + pattern match, `from` queries with `is_nil/1`, or guard clauses.
- **Fix Vix 0.26 API incompatibility**: `Vix.Vips.Image.width/1` and `height/1` now return plain integers, not `{:ok, integer}` tuples. The `with` chain in `generate_variant` and both `resize/3` clauses were matching `{:ok, w}` which silently fell through as a no-match, leaving media items stuck at `processing_status: "processing"` forever.
