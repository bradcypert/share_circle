---
"share_circle": minor
---

Invitations UI — send, list, and revoke from Members page

- MembersLive now loads pending invitations and exposes invite form for owners and admins
- Invite form: email input, role selector (member/admin/limited), inline error display
- Pending invitations section lists email, role, expiry date with a Revoke button
- Revoke calls Families.revoke_invitation/2 and refreshes the list
- Fixed TODO in Families.invite_member/3: invitation email is now sent via UserNotifier after the record is created; accept URL is built from Endpoint.url() + verified route
- Added UserNotifier.deliver_invitation_instructions/3 with a plain-text invitation email
