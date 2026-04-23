---
"share_circle": minor
---

Phase 6a: Quota enforcement, setup wizard, onboarding, and admin dashboard

- Migration: add is_admin to users
- First registrant automatically becomes instance admin; subsequent admins toggled via admin dashboard
- Family quota defaults (storage_quota_bytes, member_limit) seeded from STORAGE_QUOTA_GB / MEMBER_LIMIT env vars at family creation time
- Member limit enforced on invitation acceptance; returns :member_limit_reached error
- SetupLive: first-boot wizard at /setup — two-step account + family creation, self-closes once any user exists
- AcceptInvitationLive: browser-based invitation acceptance at /invitations/:token/accept, redirects to onboarding
- OnboardingLive: post-join welcome screen at /families/:id/onboarding — set display name + feature tour
- AdminLive: instance admin dashboard at /admin — families tab (storage/member usage, inline quota editor) and users tab (admin toggle)
