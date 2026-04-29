---
"share_circle": minor
---

Add user profile customization

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
