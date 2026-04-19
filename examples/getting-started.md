# Project Kickoff Notes

**Date:** 14 April 2026  
**Attendees:** Sarah Chen, Marcus Webb, Priya Nair

---

## Goals for This Sprint

The team aligned on three priorities for the next two weeks:

1. Finalise the data model and get sign-off from the product team
2. Stand up the staging environment so QA can begin testing early
3. Resolve the outstanding API authentication issues before the client demo

## Key Decisions

- **Database:** Sticking with PostgreSQL — the migration cost to Mongo isn't justified at this scale
- **Auth:** Moving to OAuth 2.0 with JWT refresh tokens; existing session-based auth deprecated end of month
- **Deployment:** Staging mirrors production (same instance type, same region) to avoid environment surprises

## Action Items

| Owner  | Task                               | Due    |
|--------|------------------------------------|--------|
| Marcus | Finalise schema and create migration | 17 Apr |
| Priya  | Provision staging environment      | 16 Apr |
| Sarah  | Draft OAuth integration spec       | 18 Apr |
| All    | Review and comment on API auth RFC | 15 Apr |

> The client demo is locked in for the 25th — that date is immovable. Flag anything at risk by end of day Wednesday.
