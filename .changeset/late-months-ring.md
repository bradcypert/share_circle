---
"share_circle": minor
---

Add supervised (child) account type with guardian-managed promotion flow

- Add `is_supervised`, `guardian_user_id`, and `promoted_at` columns to users
- Add `child` role between `limited` and `member` in the family RBAC system
- Child accounts are created directly by guardians (owners/admins); the child receives a 7-day activation email to set their own password
- Guardians, owners, and admins can manually promote a child to a full member; the child receives a promotion email, sets a new password (optionally updating their email), and all child memberships are atomically upgraded to `member`
- Guardian is notified by email when the child completes promotion
- New unauthenticated LiveViews: `/users/activate/:token` and `/users/promote/:token`
- Members page gains an "Add child" form and per-member "Promote" button with confirmation modal
