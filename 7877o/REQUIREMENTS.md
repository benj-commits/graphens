# Graphens product requirements

**Status: proposed, not implemented.** Scope: `7877o` Flutter customer app, supporting backend, courier operations and admin website. This document is not authorization to deploy or alter live services.

## Outcome and prerequisites

Real products, trusted prices/payments, delivery and genuine fulfilment. Never portray simulations as real. Unavailable dependencies must show honest unavailable/pending states. Production needs owner approval, verified build/backend, provider onboarding and end-to-end tests.

Main has corrupted paths per repair work; [PR #24](https://github.com/benj-commits/graphens/pull/24) (`fix/apk-build-repair`) is an unmerged draft. Resolve separately; it restores an earlier flow, not admin-managed fees, warns of debug signing and not to run `full_setup.sql` as a migration.

Prior code review reports local-only reviews/wishlist/location; fixed unsaved delivery labels; fake fee and confirmation; MTN/Airtel labels only; local order ID; online status without rider location; hardcoded `GRAPHEN10`; greeting, WhatsApp link and optional post-login biometric. These are code observations, **not proof of production behaviour**; verify the baseline.

Supabase is reportedly paused; actual availability, project, schema, RLS, integrations and data are unverified. Authorized owners must verify and decide restoration safely. Obtain approved Supabase/staging access, MTN/Airtel merchant accounts/credentials or authorized aggregator, courier API/commercial access, support number, website/admin ownership and brand assets. Separate test/production; this document authorizes no credentials use or live changes.

## Functional requirements and acceptance criteria

### Shared ratings and reviews

Signed-in customers submit ratings/optional reviews, edit/delete their own and see shared rating/count. Agree range, purchase eligibility, uniqueness, moderation and abuse controls.

**Acceptance:** A's saved review appears to B and after A signs in on another device; aggregates reflect permitted reviews. B cannot change A's. Invalid inputs are rejected; show loading/empty/error states, never a failed write as saved. Enforce eligibility/uniqueness server-side.

### Customer location and delivery pin

Clarify whether "GPRS" means GPS delivery pin, continuous customer tracking, or both: GPS is positioning; GPRS is mobile data. Default to one-time address/pin; continuous tracking requires separate purpose and informed opt-in. Explain purpose, recipients, retention and withdrawal before permission. Offer manual entry and pin correction; persist authorized location only for permitted delivery parties.

**Acceptance:** denied/revoked permission, disabled/inaccurate GPS offers manual entry without background collection. Pin survives restart on correct order; other customers cannot read it. Withdrawal stops optional tracking and triggers retention/deletion process without breaking agreed delivery. Minimize precision/access/retention; encrypt in transit/at rest, avoid location logs, publish privacy notice and support access/deletion subject to law. Obtain legal/privacy review.

### Delivery date and time

Offer server-validated real slots in the delivery area's local time with timezone, cutoffs and capacity; persist across sessions/devices.

**Acceptance:** selected date, time and timezone match at review, after restart and in order details. Reject past, invalid or full slots; if capacity changes offer another before confirmation. Test timezone and daylight-saving conversions.

### Transport allocation and charges

"Fuwas charges" is undefined: identify provider, authoritative price source, model, currency, availability, terms and API access. Never invent quotes. Server calculates fee from authorized tariff or verified provider quote; show currency, fee, expiry and total before approval. Define fallback and renewed acceptance of changes.

**Acceptance:** reject tampered fees and invalid/expired quotes; changes require renewed approval. Mark assigned only after verified provider/authorized operator acceptance. Show pending, unavailable and failure honestly, without fabricated courier.

### Account, welcome and biometrics

Greet authenticated returning customers by profile name, with generic fallback and no shared-device leakage. Optional biometric unlock follows normal login and opt-in using OS APIs and secure storage; never collect/transmit templates. Provide secure normal login/device-credential fallback per platform policy and opt-out.

**Acceptance:** only OS success unlocks. Unsupported hardware, missing/changed enrollment, cancellation and lockout use safe fallback without bypass. Logout clears unlock authorization and sensitive session material; account switch shows correct greeting.

### Account-synced wishlist and cart

Signed-in users add/remove from product cards and detail, remove or move an available item to cart from wishlist, and save/remove from an appropriate cart action. All entry points share account state with feedback, loading and recoverable errors.

**Acceptance:** sync across devices and reinstall; enforce account/product uniqueness and idempotent writes under concurrent taps. Roll back failed optimistic writes or mark unsaved. Deny other accounts. Prompt guests to sign in; resume only with consent or ask again, never claim guest sync. Show trusted current price/stock; allow removal of unavailable items but block or revalidate cart/checkout additions. Wishlist does not reserve stock.

### WhatsApp support

Provide a labelled, user-initiated link to the approved business number. Prefilled text excludes personal/order/location data unless chosen by the customer.

**Acceptance:** opens WhatsApp or web fallback; otherwise show alternate contact. Number is configurable and owner-verified; no message is sent automatically.

### Real checkout and verified MTN/Airtel payments

Server validates cart, stock, authoritative prices, delivery quote/slot and voucher, generates durable order ID and itemized total/currency. Reserve or revalidate stock under an approved expiry policy. Never trust client totals, IDs, discounts or payment success.

Integrate real MTN and Airtel Request to Pay via approved APIs or authorized aggregator after onboarding, documentation and compliance verification. Sandbox both; production requires contracts, credentials, certification and approval. A label or request initiation is not payment; customer authorizes via provider.

Use persistent server-side idempotency key per intended attempt, provider reference and transactional state. Repeated taps, timeout, reconnect, retry and replay must not duplicate charges/orders. Reconcile uncertain outcomes before a new charge; show pending, never silently retry. Agree late success, cancellation, failure, overpayment and refund handling.

Authenticate callbacks using documented provider signature/authentication and transport; validate merchant, reference, amount, currency and expected state; deduplicate events and resist replay. Verify server-to-server where supported and reconcile missing/delayed callbacks. Reject forgery/mismatches, audit safely and keep secrets/service-role keys off clients.

**Acceptance:** sandbox-test both providers: initiation, authorization, verified success, decline, cancellation, timeout, missing/delayed callbacks, replay, concurrent taps and outage. One intended payment produces at most one charge/order. Forged/mismatched events cannot mark paid; reconcile lost responses. Reject tampered totals and stale stock/quotes. Production certification and approval precede real payments.

### Order states and live courier tracking

Separate server-authoritative payment states (unpaid, pending, paid, failed, cancelled/refunded) and fulfilment states (awaiting confirmation, confirmed, preparing, dispatched, delivered, cancelled). Define transitions/actors and timestamped audit. Initiation is not payment. Green **confirmed** requires durable server evidence of all approved conditions, including verified payment where required and genuine fulfilment acceptance. Never show pending/failed/cancelled as green. Restore state from server and use its order ID.

Customers see verified real-time progress for first and later orders. With assigned courier's informed consent, show actual location for active delivery only, timestamped and freshness-labelled, restricted to that customer/order; stop on completion, withdrawal or approved cutoff. This consent differs from customer GPS consent.

**Acceptance:** first/later orders show correct status, survive logout/reconnect and recover missed updates; deny unauthorized access/subscriptions. Delayed/disconnected feeds show last update and stale/unavailable, never simulated movement. No location before consent/assignment or after access ends. Duplicate events do not double-transition; unpaid or unaccepted orders are not green/confirmed.

### Admin website vouchers

Authorized admins create/edit/disable/audit website vouchers: code, type/value, validity/timezone, eligibility, minimum spend and usage limits. No hardcoded universal code or client discount is authoritative. Server validates, computes discount and atomically enforces global/per-user redemption limits, associating usage with an order; define rollback on cancellation/failure.

**Acceptance:** website-created eligible code works in app, shows correct discount before approval and persists in order. Expired, disabled, ineligible, exhausted or tampered codes fail clearly. Concurrent redemptions cannot exceed limits; customers cannot manage vouchers and changes are auditable.

### Branding and fast journeys

Use owner-approved custom icon and dark brown palette with accessible contrast/controls and legible platform sizes. Reduce steps/re-entry without sacrificing consent, price review, confirmation or authorization. Make first and later orders reliable; measure speed, not guarantee latency. Ask whether "very first orders" means **very fast orders**, the customer's **first order**, or both.

**Acceptance:** icon renders at supported sizes; palette passes agreed contrast checks. Usability tests complete first/returning orders without misleading success, unnecessary navigation or redundant entry; record steps, errors and duration and agree targets after baseline. Interruptions preserve safe state and offer recovery.

## Backend, security and performance

Baseline catalog/search, wishlist, checkout, history and updates on representative data/devices/networks; agree percentile targets, without guaranteed latency or claims about current Supabase. Use query plans for measured indexes, bounded pagination, efficient queries, appropriate caching with freshness/invalidation, and authorization-scoped realtime subscriptions; test index costs, load, reconnect and backfill.

Monitor p50/p95, errors, availability, payment reconciliation, event lag and location freshness with privacy-safe IDs, alerts and runbooks. Never log secrets, biometrics or precise location. Test RLS on exposed tables, least-privilege server authorization and customer/admin/courier isolation. Store service-role/provider secrets server-side, never clients; use TLS, encryption at rest, backups/restore, rate limits and input validation.

Inspect deployed schema first; use reviewed/versioned, reversible or forward-repairable migrations, compatibility checks, staging, backup and rollback. Never run full setup blindly in production. Explicit approval and monitoring precede release.

**Acceptance:** load/query-plan reports compare before/after against agreed budgets; pagination is stable, invalidation returns correct prices/stock and reconnect restores order state. RLS denies unauthenticated/cross-user and forged admin/courier access. Staging migration/restore passes with approved rollback; monitoring detects outages/stale events without leaking secrets.

## Milestones and dependencies

1. Discovery: clarify decisions; safely inspect repair, app and live state; obtain approved access, merchant/courier accounts and assets. Do not assume PR #24 or Supabase is live.
2. Foundation: repair, staging, migrations, auth/RLS, monitoring, server orders/prices, restore and production signing.
3. Essentials: reviews, wishlist, pin/slot, branding, greeting/biometrics and support; test isolation/failure.
4. Commerce: real transport, website vouchers, MTN/Airtel sandbox payments, verified status and consented courier tracking.
5. Launch: certification, privacy/security review, end-to-end tests, measured performance, reconciliation/runbooks, rollout and explicit owner approval. Disable unavailable real-money features rather than simulate.

## Test plan and evidence

- Unit: calculations, timezone/slots, state transitions, vouchers, idempotency and uniqueness.
- Integration: RLS across two customers/admin/courier; sync, website vouchers, pricing/allocation, secure callbacks/replay/concurrency, reconciliation and staging migration/restore.
- Devices: first/later orders, GPS denial/manual pin/withdrawal, slots, biometric failure/logout, stock, WhatsApp, icon/contrast, offline/reconnect, stale tracking and dependency failure.
- Trace server-generated orders through sandbox payments/callbacks and fulfilment; test success/pending/failure and courier consent/access. Sandbox is not live; certify production separately.
- Record environments, defects, p50/p95, security/privacy sign-offs, restore/rollback and owner go/no-go; exclude credentials and personal location.

## Unresolved owner decisions

1. What is "fuwas": provider, pricing source, currency, allocation, access and fallback?
2. Does "GPRS" mean delivery pin, continuous customer tracking, or both? What consent/retention rules and courier consent/withdrawal apply?
3. Does "very first orders" mean **very fast orders**, the customer's **first order**, or both? What targets follow baseline measurements?
4. Which MTN/Airtel APIs or authorized aggregator, merchant accounts, callback verification, fees and certification apply? What constitutes confirmation and how are uncertain payments/refunds handled?
5. What are delivery zones, slots/capacity, quote expiry, stock reservation, voucher limits and review eligibility/moderation?
6. Who owns Supabase, admin website, courier operations and WhatsApp; what is their deployed status and authorized access? Which icon and exact dark brown palette are approved?
