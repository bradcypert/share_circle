---
"share_circle": patch
---

Credo strict-mode cleanup — zero F/R issues remaining

- **Fix compiler warning**: Added `@impl true` to `ProfileLive.handle_info/2`.
- **Fix `[F]` unless+else**: Converted `unless user.is_admin do ... else` to `if` in `AdminLive.mount`.
- **Fix `[F]` deep nesting** (10 functions refactored): Extracted private helpers to reduce nesting depth in `ProfileLive.mount`, `ChatLive.mount`, `NotificationsLive.handle_event`, `FeedLive.handle_info({:comment_deleted})`, `EventsLive.handle_info({:rsvp_updated})`, `Posts.create_post`, `Chat.ensure_family_conversation`, `ProcessImage.do_process`, `ProcessImage.generate_variant`, and `ProcessImage.resize`.
- **Fix `[F]` cyclomatic complexity**: Replaced the `case kind do` dispatch in `NotificationsLive.notification_text` with pattern-matched `notification_message/2` clauses, reducing cyclomatic complexity below threshold.
- **Fix `[R]` single-clause with+else**: Converted to `case` in `Accounts.get_user_by_api_token`, `AuthController.confirm_password_reset`, and `LocalBlobController.upload/download`.
- **Fix `[R]` implicit try**: Removed explicit `try do` wrappers from `Posts.decode_cursor` and `Chat.decode_cursor`, using function-level `rescue` instead.
- **Fix `[R]` missing @moduledoc**: Added `@moduledoc false` to `AppComponents`, `UserChannel`, `FamilyChannel`, and `ConversationChannel`.
- **Fix `[R]` alias ordering**: Sorted aliases alphabetically in `RateLimit`, `LoadCurrentFamily`, and `RsvpController`.
- **Fix grouping warnings**: Moved extracted `defp` functions after the `handle_info` catch-all clause to keep all public callbacks grouped together.
