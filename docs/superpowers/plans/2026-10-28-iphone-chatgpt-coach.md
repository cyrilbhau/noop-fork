# iPhone Coach with a ChatGPT subscription — implementation plan

Date: 2026-10-28. Status: implemented, installed on iPhone, and normal Coach chat accepted by the owner.

User scope: a personal, locally installed iPhone build. Android, Apple Watch, public distribution,
and a macOS product integration are excluded. Shared Swift sources must still compile for the
existing macOS target. The user has explicitly authorized this personal-fork exception to the
upstream bring-your-own-key scope; an upstream issue or distribution approval is not a prerequisite.

The intended result is a **ChatGPT subscription** provider in Coach with a **Continue with ChatGPT**
button. After browser authorization, Coach uses the user's eligible plan without an API key or a
NOOP-operated backend. Existing API-key and Custom providers remain available. Existing health-data
consent, local conversation storage, and on-device dictation continue to apply.

## 1. Establish the baseline and prove iPhone sign-in first

The first deliverable is a small vertical slice on a physical iPhone, before broad engine/UI work.
OpenAI documents personal local projects, but its direct sign-in flow requires an HTTP callback on
`127.0.0.1`; it does not document a separate native iOS flow. Apple's standard authentication callback
matching documents custom schemes and HTTPS. Native iPhone feasibility is therefore an empirical
gate, not an established guarantee. [OpenAI availability](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt),
[OpenAI callback contract](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
[Apple authentication session](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/).

- [ ] Record the current branch, dirty-file baseline, installed iPhone iOS version, signing setup,
  and baseline iOS build. Preserve all unrelated edits, particularly `project.yml`,
  `StrandiOS/Resources/Info.plist`, and `Strand/Resources/Localizable.xcstrings`.
- [ ] Build a minimal debug-only Connect/Test surface using the production auth primitives below.
  Start a short-lived `NWListener` bound **only to 127.0.0.1**, using an available port and the fixed
  path `/auth/callback`. Wait for listener readiness before opening authorization. Limit request
  size, accept the expected GET path, validate state, handle duplicate callbacks once, and close
  the listener on success, cancel, timeout, or unrecoverable failure.
- [ ] First test a retained, presented `ASWebAuthenticationSession` with no scheme callback matcher
  and let the independent listener receive the HTTP callback. After a valid callback, explicitly
  dismiss/cancel the browser session with exactly-once completion arbitration. This arrangement is
  a prototype hypothesis; neither source establishes that it works on iOS.
- [ ] Verify a complete flow: browser consent, loopback delivery while the browser UI is presented,
  issued client ID, token exchange, verified ID token, granted plan scope, account model discovery,
  and one explicit test prompt ending in `response.completed`. The test prompt contains no health
  data. The user's browser interaction is required when implementation reaches this stage.
- [ ] Verify cancel/retry, a returning sign-in, app relaunch, interruption by another app, and token
  renewal when permitted. Capture only sanitized outcomes and OS/build versions.
- [ ] If the first browser presentation cannot receive the callback, assess a presented
  `SFSafariViewController` with the same listener, subject to the documented browser requirements.
  External Safari plus a finite background task is not a dependable multi-minute login design.
  Do not substitute `noop://`, an invented HTTPS callback, an undocumented device-code flow, a
  token copied from Codex/ChatGPT, or a backend proxy.

**Exit condition:** repeatable sign-in and completed inference on the user's iPhone through the
documented OpenAI contract. If this cannot be demonstrated, record the actual failure and supported
options before spending effort on the remaining integration. The plan does not promise a zero-loss
replacement before this gate passes. No Bonjour/multicast permissions, broad ATS exceptions, or
extra background modes are planned for the local callback.

## 2. Add an isolated authentication and session layer

Keep runtime networking in app targets. Proposed files:

| File | Responsibility |
|---|---|
| `Strand/AI/ChatGPT/ChatGPTAuth.swift` | Pure authorization/token request builders, scopes, registration records, callback parsing, token-response decoding |
| `Strand/AI/ChatGPT/ChatGPTIDTokenVerifier.swift` | OIDC discovery/JWKS retrieval and strict identity verification |
| `Strand/AI/ChatGPT/ChatGPTCredentialStore.swift` | Keychain persistence for credentials and registration/host records |
| `Strand/AI/ChatGPT/ChatGPTSession.swift` | Serialized session lifecycle, refresh, account selection, revocation, and observable status |
| `StrandiOS/App/ChatGPTSignInCoordinator.swift` | Browser presentation, retained authentication session, listener lifecycle, cancellation |
| `StrandiOS/App/ChatGPTLoopbackListener.swift` | Restricted one-attempt HTTP listener; no general server or LAN binding |

- [ ] Use first-time `client_id=dynamic_agent_client`, `agent_name_hint=Noop`, and a persistent
  `ext_agent_host_id=urn:uuid:<UUIDv4>` for this installation. Save the issued callback `client_id`
  before code exchange, and reuse it for reauthorization. Keep it if an authorization code expires.
- [ ] Use fresh cryptographically random state, nonce, and S256 PKCE for every attempt. Request
  `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`, with resource
  `https://api.openai.com/v1`. Use the exact callback URI in authorization and token exchange;
  across attempts only its port may vary. Never replace `127.0.0.1` with `localhost`.
- [ ] Authorize at `https://auth.openai.com/api/accounts/authorize`; form-POST the authorization-code
  exchange to `https://auth.openai.com/api/accounts/oauth/token`. No client secret is introduced.
- [ ] Verify signature, issuer, audience matching the issued client ID, expiration, and the saved
  nonce before accepting identity. Use discovery at
  `https://auth.openai.com/.well-known/openid-configuration` and its JWKS URI. Reject unsigned tokens,
  disallowed algorithms, untrusted key URLs, and mismatched accounts. Cache signing keys and perform
  a bounded refresh for an unknown `kid`.
- [ ] Use pinned **JOSESwift 3.0.0** for JWS/JWK primitives, with explicit claim validation in the
  verifier. It supports iOS 13+ and macOS 10.15+, fitting the existing targets; do not implement
  signature algorithms or accept a decoded-but-unverified JWT. Add the dependency through
  `project.yml`, preserve its existing edits, and regenerate the project.
  [Package manifest](https://github.com/airsidemobile/JOSESwift/blob/3.0.0/Package.swift),
  [JOSESwift documentation](https://github.com/airsidemobile/JOSESwift/blob/master/README.md).
- [ ] Store access, refresh, and ID tokens, expiry, granted scopes, and verified identity in a
  dedicated Keychain service using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Keep host ID
  and issued registration mapping stable across ordinary restarts/sign-outs. Keep separate records
  keyed by issued client ID plus verified issuer/subject, even when emails match. One profile is
  active; a compact account selector can reconnect a saved profile or add another.
- [ ] Use `SecItemUpdate` for existing credential records and an add path for first save; avoid a
  delete-before-add rotation that loses the prior refresh token on a failed write. Publish a ready
  state only after persistence succeeds. If OpenAI already rotated the token and the Keychain write
  fails, the old stored refresh token may be unusable: retain the replacement only in memory for a
  bounded storage retry, surface a credential-save failure, and require reconnect after process loss
  rather than silently falling back to the old token. Do not put secrets in preferences, `.noopbak`, SQLite,
  App Groups, widget snapshots, exports, URL logs, or analytics.
- [ ] Serialize refreshes in `ChatGPTSession`, share one in-flight refresh among concurrent callers,
  honor expiry and `earliest_refresh_at`, and atomically replace rotating credentials. Confirm the
  latter field's wire representation, units, optionality, and timing semantics against the actual
  documented/token contract during the spike; do not guess an epoch or force an early refresh on 401.
  Handle a missing field explicitly. Refresh with
  issued client ID, resource, and refresh token; omit scope. Clear unusable tokens after terminal
  refresh errors, while transient network failures retain credentials and allow retry. Validate any
  replacement ID token's signature/claims and original registration identity; a refresh has no new
  authorization-attempt nonce. Do not run a renewal timer while Coach is idle.
- [ ] On sign-out, invalidate the request generation, cancel active inference, and attempt refresh-
  token revocation through discovery's revocation endpoint. Coordinate with an in-flight refresh so
  revocation uses the newest token, including a late replacement; revoking only an obsolete predecessor
  is insufficient. Clear local secrets and ID-token hints;
  retain registration/host mapping. Report if remote revocation could not be confirmed. Keep local
  chat deletion separate from disconnect so reconnecting does not destroy conversations.

The session exposes status rather than tokens to SwiftUI: signed out, authorizing, signed in without
plan permission, ready, refreshing, reauthorization required, unavailable, and usage limited. A valid
ID token alone never enables inference. Do not reuse the Oura OAuth provider: it is compiled out by
default, has a different callback and grant contract, and is not a PKCE implementation.
[Sign-in contract](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
[session lifecycle](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions),
[token fields](https://developers.openai.com/siwc/token-sharing-open-source/token-reference).

## 3. Implement the subscription transport and model catalog

Create `Strand/AI/Providers/ChatGPT.swift` and
`Strand/AI/ChatGPT/ChatGPTResponsesStream.swift`. Inject session, clock, credential store, and transport
seams so failures and races can be tested without a live account.

- [ ] Fetch account models with the same OAuth bearer credential used for inference. This response
  uses `models[]`, not the API-key parser's `data[]`. Preserve server order, filter
  `visibility == "list"`, display `display_name`, and send `slug`.
- [ ] Keep catalog and selected model per registration. Use the previously selected slug if still
  available; otherwise select the first listed model and show the selection. Do not seed subscription
  choices from Noop's hard-coded API-key model list. Refresh on explicit connection/account changes
  and the existing refresh action; prevent late responses from a prior profile overwriting state.
- [ ] Send only to public `POST https://api.openai.com/v1/responses` using OAuth bearer auth. Build a
  dedicated request with `store:false`, `stream:true`, local history in an `input` array, and the
  Coach prompt in `instructions`. Do not reuse Chat Completions request bodies or backend endpoints.
- [ ] Omit unsupported parameters, including `temperature`, `max_output_tokens`, `background`,
  `conversation`, and `previous_response_id`. Keep brevity instructions and existing local history
  compaction; do not promise the existing provider's 4096-token request cap on this route.
- [ ] Parse complete SSE events with line-ending/fragment handling. Emit `response.output_text.delta`;
  accept success only after `response.completed` and nonempty reply text. Treat failed/incomplete
  terminal events, explicit errors, malformed events, cancellation, and premature EOF as failures.
  Preserve partial foreground replies with the existing interrupted marker; headless callers receive
  no successful result for partial output. Do not duplicate text from both delta and terminal events.
- [ ] Implement both `stream` and `send` through this transport. `send` accumulates the stream and
  returns only after verified completion. This supports scheduled briefs and dropped-history summaries
  without using a nonstreaming HTTP mode.
- [ ] Decode both structured errors and admission `detail` bodies. Distinguish expired auth,
  missing plan permission/eligibility, account/model policy, usage limits, transient failures, and
  network interruption. A `403` does not automatically mean an invalid API key. A `429` pauses work
  and offers Manage usage without inventing reset times or repeatedly reauthorizing.
- [ ] Allow at most one auth refresh/retry after an authentication rejection before output begins.
  Never replay a partially generated answer automatically, silently change providers, or fall back
  to billable API-key usage. Retry temporary failures only with a small bounded policy before output.
  Retain sanitized status/code/request ID for diagnosis, excluding request contents and credentials.

The existing `performStreamingRequest` is unsuitable unchanged: its callback cannot propagate event
errors, it maps both 401/403 to `badKey`, and EOF counts as success. Use a separate Responses transport
so existing provider behavior does not regress.
[Model and inference contract](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference),
[preview restrictions](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations),
[errors](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery).

## 4. Connect all Coach paths and the iPhone UI

Primary existing seams: `AIProvider`/`AIProviderClient` in `Strand/AI/AIProvider.swift`;
`AICoachEngine.isConfigured`, `resolvedKey`, `callProvider`, and `streamProvider` in
`Strand/AI/AICoach.swift`; `CoachView`, `CoachSettingsView`, and `CoachLauncherSheet` in
`Strand/Screens/`.

- [ ] Add a distinct `chatGPT` provider identifier; keep the existing `openAI` API-key option. Add
  a platform-filtered selectable-provider list so the new connection UI is offered only on iOS.
  Guard platform-specific presentation code and handle enum exhaustiveness in shared Swift.
- [ ] Replace key-only readiness with provider-aware connection status. A ChatGPT session resolves
  credentials exclusively through `ChatGPTSession`, never `AIKeyStore`, its legacy ownerless-key
  fallback, or a placeholder string. Existing cloud-key and keyless Custom paths retain their behavior.
  Introduce a typed connection resolver with an existing-client/credential branch and a ChatGPT
  session-reference branch. Leave `AIProviderClient` unchanged for existing clients; the new
  `ChatGPTClient` accepts a registration reference and asks the session actor for a token internally.
  Replace `AIProvider.client` with an optional legacy-client accessor (`nil` for ChatGPT), and update
  its four engine call sites through the resolver. This avoids dummy API keys or global session state.
- [ ] Capture provider, model, active profile, and request-generation identity at operation start.
  Recheck the master switch and relevant consent at actual request dispatch after async context or
  token refresh. Invalidate tasks on sign-out, profile/provider changes, or master-off. Prevent old
  deltas, catalog results, or refreshed credentials from being applied to a different active session.
  Reconnecting the same profile retains the current transcript. If the user chooses a different
  registration, clearly start a new conversation rather than silently replaying the prior profile's
  transcript or dropped-history summary into the new connection. No multi-account chat archive is
  required; preserve the existing single-current-conversation model.
- [ ] Route foreground `send`, empty-chat `startBriefIfNeeded`, headless `generateBrief`, and
  `summarizeDroppedMiddleIfNeeded` through the same authenticated adapter. Add the missing master-switch
  guard to the opening-brief path. Preserve day rollover, history window/summary behavior, local
  persistence, advice save/copy/share, and metric/workout/on-device-signal context builders.
- [ ] Replace key-editor/repair controls with Continue with ChatGPT, active-account identification,
  model selection, reconnect, and disconnect when this provider is selected. Update every model-refresh
  button currently disabled by `hasKey`. Use published session state so Keychain changes update the UI.
  Replace the setup screen's segmented provider control with an iPhone-friendly menu/list if a fifth
  provider cannot fit legibly; retain the existing provider labels and selection semantics.
- [ ] Show a one-time plan-use confirmation, a compact Using ChatGPT plan status, and a Manage usage
  action opening `https://chatgpt.com/settings/usage`. Missing scope offers explicit consent renewal;
  usage limits offer management/retry without a key editor. Do not add a fabricated quota meter.
- [ ] Connecting retrieves identity and model availability; it does not grant health-data consent or
  automatically send a health-bearing test. Existing empty-chat brief generation remains conditional
  on the master switch and existing data consent. Preserve the launcher rule that opening its sheet
  alone sends no provider request.
- [ ] Reuse `StrandPalette`, `StrandFont`, and shared controls. Add strings to the existing localization
  catalog without disturbing user edits. If new files are iOS-only, keep them under `StrandiOS/`.

Baseline parity is the current text-based OpenAI Coach. On-device dictation remains unchanged. Image
attachments, ChatGPT memories/conversation import, hosted tools, agentic raw-signal work from draft
specs, and new notification features are outside this implementation.
[Required connection UI](https://developers.openai.com/siwc/ui-ux-guidelines).

## 5. Preserve scheduled briefs under iOS lifecycle limits

Modify `Strand/System/CoachBriefScheduler.swift` and the existing registration/foreground hooks in
`StrandiOS/App/StrandiOSApp.swift` only where needed.

- [ ] Reuse the current morning schedule, deduplication, stored-brief delivery, and foreground catch-up.
  The app consumes a normal Responses stream inside its permitted background work; it never sends
  the unsupported Responses `background` field.
- [ ] Use one task-expiration handler that cancels the worker/HTTP stream and finishes the BGTask
  exactly once. The current worker overwrites the cancellation handler with a completion-only handler;
  fix that at this integration boundary.
- [ ] Propagate cancellation through refresh, inference, aggregation, and publication. Check cancellation
  before storing a brief, marking its day successful, or posting a notification. A cancelled/partial
  result must never be announced as completed advice.
- [ ] Refresh silently if possible; never present browser sign-in from a background task. If tokens
  require reauthorization, leave a reconnect state for the next foreground session, preserving the
  existing catch-up policy. Do not create background retry loops for plan exhaustion.
- [ ] Verify refresh and generation after the phone has been unlocked once and subsequently locked.
  Before first unlock, inaccessible Keychain data is unavailable rather than an instruction to erase
  credentials. Exact morning wake time remains subject to iOS scheduling, as in the current app.

No Apple Watch work or new widget implementation is included. Existing stored brief/notification
consumers continue to receive only completed results; tokens never enter their shared storage.

## 6. Validate the integration and document the personal exception

Create focused `StrandTests/ChatGPTAuthTests.swift`, `ChatGPTSessionTests.swift`,
`ChatGPTResponsesTests.swift`, `AICoachChatGPTTests.swift`, and scheduler cancellation coverage.
Use injected transport/Keychain/clock seams and signed test JWT fixtures; do not use the personal
credential store from unit tests.

| Area | Required evidence |
|---|---|
| Authentication | Correct initial/returning registration, PKCE/state/nonce, malformed and duplicate callbacks, cancel/timeout, client/account mismatch, JWT signature/issuer/audience/expiry/nonce rejection, JWKS rotation |
| Credentials | Remote rotation followed by save failure, atomic refresh, concurrent refresh deduplication, missing/early refresh timing, terminal versus transient failure, latest-token revocation during refresh/sign-out, no late write after disconnect, locked-store handling |
| Catalog | `models[]` schema, visibility and order, display labels versus slugs, account-specific selection, empty catalog, stale refresh after profile change |
| Responses | Correct body with forbidden fields absent, foreground/aggregated equivalence, fragmented/CRLF SSE, terminal success, failure/incomplete/EOF after partial text, refusal/empty output, no duplicate text, cancellation and bounded retry |
| Coach behavior | All four call paths reach the new adapter, master/data-consent gates, preserved context/history/day rollover/summaries, no API-key fallback, no late output after session/provider change |
| Background briefs | Expiration cancels transport; completion happens once; no partial brief success/notification; reconnect never opens UI; dedup and catch-up remain valid |
| Existing providers | Relevant current API-key/Custom Coach tests continue to pass; no secret ownership regression |

- [ ] Regenerate with `xcodegen generate`. Build `NOOPiOS` for an available iPhone simulator and the
  physical device configuration. Existing `StrandTests` is a macOS-hosted app test target: run the new
  shared auth/transport tests and relevant existing Coach/scheduler tests there. This also validates
  shared Swift compilation; it is not a commitment to deliver the sign-in UI on macOS.
- [ ] Do not claim `swift test` alone validates app-target code. Test the iOS-only listener and browser
  lifecycle on the physical iPhone; macOS tests and simulator builds cannot establish that behavior.
- [ ] On the user's phone, test connect, cancel/retry, account/model selection, a metric-grounded chat
  with consent, a chat without health consent, follow-up/history across relaunch and day rollover,
  voice dictation, Generate now, background/foreground brief delivery, interrupted connectivity,
  reconnection, and disconnect. Trigger quota/policy faults through stubs rather than exhausting the
  user's real allowance. Use a phone lock/background test for cancellation and credential access.
- [ ] Run source hygiene and localization checks appropriate to changed files. Do not run Android or
  Watch builds. Keep generated Xcode projects/build output out of git, and preserve unrelated work.
- [ ] Update the personal fork's Coach notes and network inventory in `README.md`,
  `docs/PRIVACY_SECURITY.md`, and `docs/SCOPE.md` to describe optional ChatGPT identity/plan permission,
  browser/auth/discovery/model/inference/revocation traffic, local callback behavior, shared plan
  limits, and the existing independent health-data consent. Record the iPhone-only personal scope
  so it does not imply upstream cross-platform parity or wider release eligibility.

**Completion criteria:** on the user's iPhone, Coach can connect and make completed model requests
with the ChatGPT subscription and no API key; text chat, health context, follow-ups, local history,
dictation, summaries, and existing brief flows work; failure/cancel/sign-out cannot leak credentials
or publish partial briefs as success; all relevant app builds/tests pass. No rollout or release work
is required.

## Delivery order

1. Real-iPhone authorization and inference proof (mandatory feasibility gate).
2. Durable auth/session layer and contract tests.
3. Responses adapter and account model catalog.
4. Coach engine/setup/settings integration for iPhone.
5. Brief cancellation/lifecycle integration and feature verification.
6. Personal documentation and final device acceptance.

After the feasibility gate, the auth/session and Responses transport work can be developed in
parallel against agreed interfaces. Engine/UI integration follows both; scheduler validation and
device acceptance finish the work.

## Implementation checkpoint — 2026-10-28

The owner completed browser authorization and verified a completed response on the physical iPhone:
"Connection verified with GPT-6.1-Sol." This establishes the native browser/loopback, verified token,
plan permission, account model discovery and public Responses path on this device. The test sent
only a greeting. The implementation agent did not extract credentials or enable health-data sharing.

The initial inference failure exposed two supported stream tolerances: a missing Content-Type and a
complete final SSE event without a trailing separator. Both are handled while still requiring an
explicit completed response and nonempty output. The stream regression suite has 15 passing tests.

Full provider integration is now implemented: account-specific model choices and labels, text chat,
existing context consent, local history, dropped-history summaries, opening briefs and scheduled
briefs. All four inference paths use the same session-aware connection boundary, with captured
provider/model/profile identity, cancellation and a single auth retry before output. Existing API-key
and Custom providers remain selectable. Subscription UI is offered only on iPhone.

Account switching requires confirmation before clearing an active conversation. Local transcript
ownership uses an opaque installation profile UUID, with serialized SQLite snapshots and a pending
  write marker so a process exit cannot relabel old account history. No identity or credentials enter
the conversation database. Cached briefs are qualified by connection ownership and generation.
Backup restore invalidates prior history ownership at the database-swap boundary. Credentials remain
in the dedicated device-only Keychain service; temporary storage unavailability can recover without
browser authorization after the phone unlocks.

Final verification passed: signed physical-iPhone build and signature verification, iPhone simulator
build, and 133 focused XCTest cases. These include 68 subscription/auth/transport/engine/scheduler
tests, 38 existing Coach regressions, 13 backup round-trip tests and 14 coordinated Health tests.
Source hygiene, whitespace and diff-scoped localization checks passed; new UI copy has translations
in all ten existing locales.

The final combined candidate includes the other chat's Hevy/Health fixes and was installed in place,
without uninstalling or resetting data. After a transient device-connection reset, installation
succeeded; automatic launch was blocked because the phone was locked. The owner opened the app and
confirmed: "Reply works; sign-in is saved." This verifies normal Coach inference and credential
persistence across the final update. Build/install evidence stays in ignored
`build/personal/chatgpt-*` paths.

Hardware checks for overnight scheduling, locked-phone generation, dictation, interrupted
connectivity, real token expiry and multiple live accounts remain separate from automated stub-based
coverage. Generate now and summaries share the tested completed-response path. Exact iOS background
wake timing remains best effort. No Android or Watch build, public release, or backend was added.

After installation, open Coach → ChatGPT subscription → Use for Coach. The saved sign-in should be
retained. Pick an account-provided model and send a question. Health summaries and daily briefs each
remain controlled by their existing explicit settings; signing in does not enable either setting.
