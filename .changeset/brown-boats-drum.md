---
"share_circle": minor
---

Phase 5: Notifications — in-app, email, and web push

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
