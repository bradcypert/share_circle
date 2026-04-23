---
"share_circle": minor
---

Frontend redesign — Notion-inspired visual identity with persistent sidebar navigation

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
