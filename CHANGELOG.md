# Changelog

## Unreleased

- Slice 2: Libraries + memberships — Library (FriendlyId slug w/ history) and Membership (role enum: owner/member). Owner membership auto-created on Library create. Dashboard (`/libraries`) as authenticated root. Scoped access; no cross-tenant leaks. 2 system tests.
- Slice 1: Devise authentication — User model, sign up / sign in / sign out, Spanish nav, letter_opener_web for dev mail, 2 system tests.
- Slice 0: Scaffold & infrastructure — Rails 8 app, Docker Compose dev, CI, linters, Devise/Solid trio/ActionText/ActiveStorage wired.
