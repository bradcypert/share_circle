# share_circle

## 0.2.0

### Minor Changes

- 9ad347f: Invitations UI — send, list, and revoke from Members page

  - MembersLive now loads pending invitations and exposes invite form for owners and admins
  - Invite form: email input, role selector (member/admin/limited), inline error display
  - Pending invitations section lists email, role, expiry date with a Revoke button
  - Revoke calls Families.revoke_invitation/2 and refreshes the list
  - Fixed TODO in Families.invite_member/3: invitation email is now sent via UserNotifier after the record is created; accept URL is built from Endpoint.url() + verified route
  - Added UserNotifier.deliver_invitation_instructions/3 with a plain-text invitation email

- 410e2c7: Phase 5: Notifications — in-app, email, and web push

  - New tables: notifications, notification_preferences, push_subscriptions
  - ShareCircle.Notifications context: create, list, mark-read, mark-all-read, preferences, push subscriptions
  - ShareCircle.Push behavior with Noop adapter (plug in real web push later)
  - ShareCircleWorkers.DeliverNotification Oban worker: dispatches email and push per user preference
  - ShareCircle.NotificationMailer for transactional notification emails
  - UserChannel (WebSocket): real-time delivery of notification.created/read events on user:{id} topic
  - Notifications hooked into Posts (new_post, new_comment), Chat (new_message), Calendar (event_created)
  - NotificationController API: list, mark-read, mark-all-read
  - NotificationPreferenceController API: list and update preferences per kind
  - PushSubscriptionController API: register and delete push subscriptions
  - Notifications LiveView at /notifications with unread badge and mark-read actions
  - Oban notifications queue (concurrency 10) added to config

- 61b59eb: Media uploads in feed posts

  - Added `PresignedPut` JavaScript uploader to `app.js` — sends files directly to presigned PUT URLs (local storage or S3) with XHR progress tracking
  - Updated `FeedLive` to accept up to 4 photo/video attachments per post via Phoenix LiveView external uploads
  - File picker in post composer with drag-and-drop support on the composer card
  - Upload preview grid with per-file progress bars and cancel buttons
  - Posts with media display thumbnail images in feed (single image or 2-column grid for albums); videos show a play button overlay
  - Media variant URLs are pre-generated on mount and updated in real-time when the background processing worker marks media as ready (via `media_ready` PubSub event)
  - Gracefully handles pending/processing state — shows "Processing…" until variants are ready

- 61b59eb: Polish and completeness tasks 10–15

  - **Typing indicator**: Added `Chat.broadcast_typing/2` and `broadcast_typing_stopped/2`; message input fires `typing` event with 500ms LiveView debounce and a 3-second server-side timer to auto-stop
  - **Feed pagination**: "Load more" button appears when `pagination.has_more` is true; appends posts and merges comment/reaction/media data
  - **Chat message history**: "Load older messages" button at top of message list; prepends older messages using cursor pagination
  - **Profile wall media**: Photo/video thumbnails now render on the profile wall, matching feed behaviour; includes "Load more" pagination
  - **Chat auto-scroll**: `ScrollBottom` JS hook scrolls to bottom on mount and on each update when already near the bottom (within 200px), preserving manual scroll position when reading history
  - **Push notification opt-in**: `PushNotifications` JS hook wires browser `PushManager.subscribe` to the LiveView; "Enable push" button on notifications page when `VAPID_PUBLIC_KEY` env var is set; subscription stored via `Notifications.register_push_subscription`

- 56c748b: Add user profile customization

  **Migration** (`20260425000001_add_profile_fields`):

  - `users`: `bio`, `location`, `birthday` (`:date`), `interests`, `avatar_media_item_id` (FK → media_items, nilify_all), `cover_media_item_id` (FK → media_items, nilify_all), `pinned_post_id` (FK → posts, nilify_all)
  - `memberships`: `relationship_label` (e.g. "Mom", "Grandpa") — per-family, not global

  **Schema & changesets**: All new fields added to `User` schema with `belongs_to` associations. `User.profile_changeset/2` extended to cast and validate all new fields. `Membership.relationship_label_changeset/2` added.

  **Context functions**:

  - `Accounts.update_user_profile/2` — already existed, now covers all profile fields
  - `Families.update_membership_label/2` — updates the caller's own relationship label in a family

  **ProfileLive** — split into two modes based on whether the viewer is the profile owner:

  - **Own profile**: inline edit form for display_name, bio, location, birthday, interests, timezone, and relationship_label; cover photo and avatar upload via the standard two-phase presign/complete flow; pin/unpin any post to show it first on the wall
  - **Other's profile**: read-only view showing all filled fields with icons, plus their posts wall

  **`<.user_avatar>` component** — new function component in `AppComponents` accepting `user`, optional `url`, and `size` (`:xs` / `:sm` / `:md` / `:lg` / `:xl`). Renders the photo when a URL is provided, otherwise falls back to an initials chip. Replaces all inline initials chips in `feed_live`, `chat_live`, and `profile_live`.

- 9ad347f: Complete UI feature tasks 1–9

  - **Invitations UI**: Send, list, and revoke family invitations from Members page with email delivery
  - **Post comments**: Expandable comment threads on feed posts with real-time updates via PubSub
  - **Post reactions**: Emoji reactions (👍 ❤️ 😂 🎉 😮) on feed posts with per-user toggle state
  - **Post edit/delete**: Inline editing and soft-delete for own posts; admins can delete any post
  - **Event edit/delete/ends_at**: Full CRUD for events including optional end time
  - **Message edit/delete**: Inline editing and delete for own chat messages
  - **Notifications back nav**: Notifications page preserves `family_id` context for accurate back navigation
  - **Mobile responsiveness**: Chat sidebar becomes full-screen overlay on mobile; bottom tab bar navigation; responsive event date inputs; fixed notification header padding

- 1c7c58d: Phase 3: Chat — conversations, messages, typing indicators, read receipts

  - New tables: conversations, conversation_members, messages
  - Family-wide conversation auto-created when a family is created or an invitation is accepted
  - Chat context with send/edit/delete messages, mark-read, and conversation management
  - ConversationChannel (WebSocket) for real-time delivery, typing indicators (typing.start/stop), and read receipts
  - Chat LiveView at /families/:id/chat with sidebar conversation list and real-time message stream
  - API endpoints: list/create/show conversations, send/edit/delete messages, mark read

- 56c748b: Add supervised (child) account type with guardian-managed promotion flow

  - Add `is_supervised`, `guardian_user_id`, and `promoted_at` columns to users
  - Add `child` role between `limited` and `member` in the family RBAC system
  - Child accounts are created directly by guardians (owners/admins); the child receives a 7-day activation email to set their own password
  - Guardians, owners, and admins can manually promote a child to a full member; the child receives a promotion email, sets a new password (optionally updating their email), and all child memberships are atomically upgraded to `member`
  - Guardian is notified by email when the child completes promotion
  - New unauthenticated LiveViews: `/users/activate/:token` and `/users/promote/:token`
  - Members page gains an "Add child" form and per-member "Promote" button with confirmation modal

- 410e2c7: Phase 6a: Quota enforcement, setup wizard, onboarding, and admin dashboard

  - Migration: add is_admin to users
  - First registrant automatically becomes instance admin; subsequent admins toggled via admin dashboard
  - Family quota defaults (storage_quota_bytes, member_limit) seeded from STORAGE_QUOTA_GB / MEMBER_LIMIT env vars at family creation time
  - Member limit enforced on invitation acceptance; returns :member_limit_reached error
  - SetupLive: first-boot wizard at /setup — two-step account + family creation, self-closes once any user exists
  - AcceptInvitationLive: browser-based invitation acceptance at /invitations/:token/accept, redirects to onboarding
  - OnboardingLive: post-join welcome screen at /families/:id/onboarding — set display name + feature tour
  - AdminLive: instance admin dashboard at /admin — families tab (storage/member usage, inline quota editor) and users tab (admin toggle)

- d75b332: Phase 7: Polish & launch prep — security hardening, release tooling, load tests, documentation

  - Security headers: CSP, Referrer-Policy, and Permissions-Policy added to all browser responses via put_secure_browser_headers; HSTS already enforced via force_ssl in prod
  - Added sobelow (Phoenix SAST) and mix_audit (dependency CVE scanning) to deps and precommit alias
  - ShareCircle.Release module for running migrations from a Docker release (no Mix required)
  - Docker entrypoint.sh auto-runs migrations on app container startup; worker sets SKIP_MIGRATIONS=true
  - k6 load test scripts in test/load/: WebSocket connections (1000 concurrent), chat throughput (100 msg/s), media upload two-phase flow
  - docs/CONFIGURATION.md: complete environment variable reference for self-hosters including quotas, storage, email, push, and operations runbook
  - CLAUDE.md updated to reflect implemented state (was still marked pre-implementation)

- 905f758: Phase 2: Media uploads and processing

  - Storage adapter pattern with local filesystem and S3 stub implementations
  - Two-phase upload flow: initiate (presigned PUT URL) → complete (create media item + enqueue processing)
  - Background processing via Oban: image thumbnail generation (thumb_256, thumb_1024) using Vix/libvips; video transcoding (thumb_256 frame, video_720p H.264) via ffmpeg
  - Posts now support media: photo, video, and album kinds with post_media join table
  - New tables: media_items, media_variants, upload_sessions, post_media
  - API endpoints: POST /api/v1/families/:id/uploads/init, POST /api/v1/uploads/:id/complete, GET /api/v1/media/:id/download

- 7a3bd05: Phase 4: Events — calendar events, RSVPs, Events LiveView

  - New tables: calendar_events, rsvps
  - ShareCircle.Calendar context with create/update/delete events and upsert RSVP
  - Policy extended: members can update/delete their own events; admins can update/delete any
  - EventController and RsvpController API endpoints under /families/:id/events and /events/:id
  - Events LiveView at /families/:id/events with create form, upcoming event list, and RSVP buttons
  - Real-time updates via PubSub: event_created, event_updated, event_deleted, rsvp_updated

- d75b332: Frontend redesign — Notion-inspired visual identity with persistent sidebar navigation

  - DaisyUI light theme updated to Notion-inspired warm palette: off-white base (#FAFAF9 equiv), charcoal text, subtle warm borders, muted terra-cotta primary accent
  - System font stack matching Notion's typography; thin scrollbars; antialiased rendering
  - Root layout simplified: minimal top nav for auth/settings pages; app_shell overlays it for family pages
  - AppComponents module: `app_shell/1` component wraps family-scoped pages with fixed 240px sidebar (desktop) + bottom tab bar (mobile); `main_class` attribute allows chat to use `overflow-hidden` for full-height layout
  - Sidebar nav: family name with initial badge, nav links (Feed, Chat, Events, Members, Notifications, Settings), user avatar + display name + hover-reveal logout
  - FeedLive template: post composer with avatar, Notion-style post cards
  - ChatLive template: conversation list sidebar + message area with avatar initials, full-height flex layout
  - EventsLive template: date badge (month + day), location icon, RSVP summary; inline create form with labeled inputs
  - NotificationsLive template: standalone centered layout with back nav, unread dot indicator, mark-read button
  - MembersLive (new): `/families/:id/members` — member list with avatar chips and role labels; links to profiles
  - ProfileLive (new): `/families/:id/members/:user_id` — Facebook-style wall with cover area, avatar, role badge, post history; "Edit profile" link for own profile
  - Posts.list_posts_by_author/3 added to support ProfileLive post wall

### Patch Changes

- 9879d38: Implement foundational authentication
- 847151a: Polish and reliability improvements (tasks 17–24)

  - **Feature**: Added service worker (`priv/static/sw.js`) for web push notifications; registered in `app.js` with `navigator.serviceWorker.register`.
  - **Fix**: `PushNotifications` JS hook clones the subscribe button before re-attaching the click listener on `updated()`, preventing duplicate event listeners from accumulating across LiveView re-renders.
  - **Refactor**: Extracted `ShareCircleWeb.LiveHelpers.build_media_urls/2` to eliminate the identical private function duplicated across `FeedLive` and `ProfileLive`.
  - **Feature**: Typing indicator in chat now resolves user IDs to display names (e.g. "Alice is typing…", "Alice and Bob are typing…") instead of the generic "Someone is typing…".
  - **Fix**: Added `phx-debounce="300"` to all `phx-keyup` text inputs across feed, chat, and members pages to reduce unnecessary server round-trips.
  - **Fix**: `ChatLive.handle_event("load_older", ...)` now guards against a nil cursor with a fast-path clause, preventing a crash if the button is clicked when no older messages exist.
  - **Feature**: `FeedLive` and `ProfileLive` schedule a `:refresh_media_urls` message every 240 seconds to regenerate presigned media URLs before the 300-second TTL expires.
  - **Fix**: All silent `{:error, _}` branches in `FeedLive`, `ChatLive`, and `NotificationsLive` now call `put_flash(:error, ...)` so users see feedback instead of nothing happening.

- 56c748b: Credo strict-mode cleanup — zero F/R issues remaining

  - **Fix compiler warning**: Added `@impl true` to `ProfileLive.handle_info/2`.
  - **Fix `[F]` unless+else**: Converted `unless user.is_admin do ... else` to `if` in `AdminLive.mount`.
  - **Fix `[F]` deep nesting** (10 functions refactored): Extracted private helpers to reduce nesting depth in `ProfileLive.mount`, `ChatLive.mount`, `NotificationsLive.handle_event`, `FeedLive.handle_info({:comment_deleted})`, `EventsLive.handle_info({:rsvp_updated})`, `Posts.create_post`, `Chat.ensure_family_conversation`, `ProcessImage.do_process`, `ProcessImage.generate_variant`, and `ProcessImage.resize`.
  - **Fix `[F]` cyclomatic complexity**: Replaced the `case kind do` dispatch in `NotificationsLive.notification_text` with pattern-matched `notification_message/2` clauses, reducing cyclomatic complexity below threshold.
  - **Fix `[R]` single-clause with+else**: Converted to `case` in `Accounts.get_user_by_api_token`, `AuthController.confirm_password_reset`, and `LocalBlobController.upload/download`.
  - **Fix `[R]` implicit try**: Removed explicit `try do` wrappers from `Posts.decode_cursor` and `Chat.decode_cursor`, using function-level `rescue` instead.
  - **Fix `[R]` missing @moduledoc**: Added `@moduledoc false` to `AppComponents`, `UserChannel`, `FamilyChannel`, and `ConversationChannel`.
  - **Fix `[R]` alias ordering**: Sorted aliases alphabetically in `RateLimit`, `LoadCurrentFamily`, and `RsvpController`.
  - **Fix grouping warnings**: Moved extracted `defp` functions after the `handle_info` catch-all clause to keep all public callbacks grouped together.

- 56c748b: Fix media upload flow and add upload previews

  - **Root cause fix**: Phoenix LiveView file inputs must be inside a `<form phx-change="...">` — without it `pushInput` never fires, `@uploads.media.entries` stays empty server-side, and `consume_uploaded_entries` always returns `[]`. Wrapped the post composer in `<form phx-submit="create_post" phx-change="validate_media">`.
  - **Add `auto_upload: true`**: Uploads begin the moment a file is selected so the XHR is done before the user clicks Share. LiveView's phx-submit gate also blocks submission until all uploads complete.
  - **Upload previews**: `<.live_img_preview>` for images (absolute inset-0 to fill the aspect-ratio container), film-icon + filename for video files.
  - **Log complete_upload failures**: Server-side errors now emit `Logger.error` instead of being silently swallowed.
  - **Fix Ecto 3.13 `nil` comparison crashes** (6 call sites): `Repo.get_by/3` raises `ArgumentError` when any keyword value is `nil` in Ecto 3.13+. Fixed every occurrence across `media.ex`, `posts.ex`, `chat.ex`, `notifications.ex`, and `conversation_channel.ex` — replacing them with `Repo.get` + pattern match, `from` queries with `is_nil/1`, or guard clauses.
  - **Fix Vix 0.26 API incompatibility**: `Vix.Vips.Image.width/1` and `height/1` now return plain integers, not `{:ok, integer}` tuples. The `with` chain in `generate_variant` and both `resize/3` clauses were matching `{:ok, w}` which silently fell through as a no-match, leaving media items stuck at `processing_status: "processing"` forever.

- 847151a: Bug fixes and code quality cleanup

  - **Fix**: `ChatLive` was calling `PubSub.subscribe` on the old conversation instead of `unsubscribe` when switching conversations — users would accumulate stale subscriptions and receive ghost messages from conversations they had navigated away from. Added `PubSub.unsubscribe/1` and fixed the call in `handle_params`.
  - **Fix**: `Posts.create_post` used `Enum.with_index` (return value unused) for side effects — changed to `Enum.with_index |> Enum.each` to correctly express intent and silence the credo warning.
  - **Refactor**: `Enum.map |> Enum.join` → `Enum.map_join` in `ChatLive.conversation_display_name` and `MembersLive` error formatting.
  - **Refactor**: Extracted `maybe_load_media_url/3` from `FeedLive.handle_info({:media_ready, ...})` to reduce nesting depth.

- 4d5450f: Add in initial config options
- 56c748b: general UX fixes and synchronization fixes
- f92b34e: foundation for families
- 833b0c1: foundational middleware for authentication
- 54db118: Setup credo and precommit checking
- 6c22f0a: Add in OAS generation from server routes
- 1200b76: implement foundational support for Posts
