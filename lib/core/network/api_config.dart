/// ─────────────────────────────────────────────────────────────────
/// Confirmed from WASFA_Driver_API_postman.json (backend team's own
/// collection). Bearer-token (Sanctum-style) auth.
///
/// NOTE: response body shapes were NOT included as examples in the
/// Postman file — only request bodies. Where a repository method
/// parses a response, treat the field names as a best guess from
/// context (route names, request field names, existing app models)
/// until you've actually hit the endpoint once and checked the real
/// JSON. Easiest way: run the app, hit the screen, and print the raw
/// map in ApiClient._send before it gets parsed.
/// ─────────────────────────────────────────────────────────────────
class ApiConfig {
  ApiConfig._();

  //static const String baseUrl = 'https://portal.apixservices.com/api/driver';
  static const String baseUrl = 'https://apixrx.com/api/driver';

  // ── Auth ──────────────────────────────────────────────────────
  static const String login       = '/login';        // POST {email, password, fcm_token}
  static const String otpRequest  = '/otp/request';   // POST {phone}
  static const String otpVerify   = '/otp/verify';     // POST {phone, code, fcm_token} -> {token, ...}
  static const String me          = '/me';             // GET
  static const String fcmToken    = '/fcm-token';      // POST {fcm_token}
  static const String logout      = '/logout';         // POST

  // ── Profile ──────────────────────────────────────────────────
  static const String profileGet      = '/profile';           // GET
  static const String profileUpdate   = '/profile';           // POST (full_name, civil_id, vehicle_type, bank_iban, ... see docs)
  static const String profileDocument = '/profile/document';  // POST multipart {slot, file}
  // CONFIRMED path from Postman (2026-07-15) — /profile/photo. BUT the
  // example body in Postman is clearly a copy-paste mistake: it's a raw
  // JSON body identical to Save Profile, with no photo/file field at all
  // and no multipart mode — can't actually carry image data like that.
  // Using multipart {file: ...} here instead, matching every other real
  // upload in this API (building-photos, profile documents). Needs
  // confirming with backend once actually hit.
  static const String profilePhoto = '/profile/photo';  // POST multipart {photo} — CONFIRMED LIVE 2026-07-15 (was guessed as {file} before, actual field name is "photo")

  // ── Home / Orders ────────────────────────────────────────────
  static const String home          = '/home';               // GET — dashboard summary
  static const String orders        = '/orders';              // GET ?tab=active|done
  static const String orderByCode   = '/orders/{code}';        // GET single order, e.g. APM10061
  static const String geocode       = '/geocode/{co}';          // GET — co = numeric order id (not code)
  static const String earnings      = '/earnings';              // GET

  // ── Live location sharing (customer app "Track Order") ──────────
  // REMOVED (2026-08-25): this was a guessed path — client confirmed
  // live via Postman that it returns a genuine 404, "The route
  // api/driver/orders/{co}/location could not be found." The entire
  // feature (MapViewModel's location-sharing timer, OrderRepository's
  // postLocation) was removed along with this, not just the constant.
  // If this feature is still wanted, ask backend for the real endpoint
  // first, then re-add it properly.

  // ── Delivery flow (co = numeric order id) ───────────────────
  static const String updateStatus = '/orders/{co}/status';         // POST {status: 'collecting'|'picked_up'|'on_the_way'} — CONFIRMED v2
  // SUPERSEDED (2026-08-18) — the per-order endpoint below needed a loop
  // of calls for anything beyond a single swap (move item #3 to #1 also
  // displaces #1 and #2, needing their own follow-up calls to fix up).
  // CLIENT-CONFIRMED: this bulk endpoint replaces it entirely — send the
  // WHOLE new sequence as an array of co (numeric) ids in one call,
  // first = top priority. Raw JSON body: {"order": [26300, 26292, ...]}.
  // Response is minimal — {"ok": true, "updated": 1} — no resulting
  // sequence handed back like the old endpoint gave, so there's nothing
  // to reconcile against; the app dictated the whole order itself, so
  // there's no ambiguity for backend to resolve differently.
  static const String reorderAll = '/orders/reorder';                 // POST JSON {order: [co, co, ...]} — CONFIRMED
  // Kept only as a comment for context — no longer called anywhere:
  // static const String reorderActive = '/orders/{co}/position';     // POST form-data {position: int} — CONFIRMED, but superseded
  static const String arrive        = '/orders/{co}/arrive';               // POST
  static const String pickupSeller  = '/orders/{co}/pickup/{seller}';      // POST — CLIENT-CONFIRMED (2026-08-19) via a real backend SQL error: {seller} is the pharmacy's numeric seller_id, NOT the name as an earlier note claimed
  // CONFIRMED v3 example body only shows `pod_photo` — method/given/signature
  // are NOT shown anymore. UNCLEAR whether they were dropped from the
  // endpoint entirely or the example is just incomplete (Postman examples
  // often show a minimal case). Keeping them as additional optional fields
  // for now rather than deleting the payment-confirmation flow outright —
  // confirm with backend whether cash/knet/link collection still happens
  // here or moved elsewhere.
  static const String finish        = '/orders/{co}/finish';                // POST multipart {pod_photo (CONFIRMED required), method?, given?, signature?}
  static const String fail          = '/orders/{co}/fail';                  // POST {reason} — CONFIRMED v3: just `reason`, no `reattempt` field anymore

  // ── Building photos ──────────────────────────────────────────
  static const String buildingPhotosGet  = '/orders/{co}/building-photos'; // GET
  static const String buildingPhotosPost = '/orders/{co}/building-photos'; // POST multipart {file, customer_id?} — CONFIRMED LIVE 2026-07-14 (the earlier "photo" field name was wrong)

  // ── Shift / vehicle / language ────────────────────────────────
  static const String shift    = '/shift';     // POST {on_shift: bool} — CONFIRMED v3 (was wrongly guessed as `online` before)
  static const String vehicle  = '/vehicle';   // POST {vehicle_type, plate_number}
  static const String language = '/language';  // POST {language: 'en'|'ar'}

  // ── Batch dispatch ─────────────────────────────────────────────
  static const String batch       = '/batch';                    // GET — CONFIRMED v2: returns {batch, stops, summary, pharmacy_stops}
  static const String batchCheck  = '/batch-check';               // GET — poll for a new batch offer
  static const String batchAccept = '/batch/{batch_id}/accept';   // POST
  static const String batchReject = '/batch/{batch_id}/reject';   // POST

  // ── Pickup (multi-stop within an accepted batch) ─────────────
  static const String pickup           = '/pickup';          // GET — CONFIRMED v2: same shape as /batch (batch, stops, summary, pharmacy_stops)
  static const String pickupStart      = '/pickup/start';     // POST — "gate" to begin the pickup flow
  // CONFIRMED v3 — REPLACES the old v2 {seller_id: int} guess entirely.
  // Both pickup endpoints now key off `seller` as a NAME string (e.g.
  // "Royal Pharmacy"), matching the {co}/pickup/{seller} URL param.
  static const String pickupPharmacy   = '/pickup/pharmacy';  // POST {seller: "Royal Pharmacy"} — marks a pharmacy collected
  static const String pickupToggle     = '/pickup/toggle';    // POST {seller: "Royal Pharmacy", picked: bool} — explicit on/off toggle, no longer "legacy"/order-based

  // ── Cash handover (Company Cash tab) ────────────────────────────
  // cashHandovers below is CONFIRMED LIVE (2026-08-11) — real shape is
  // { handovers: [{co_id, code, amount (string!), status, confirmed,
  // confirmed_by, handover_date, date_label}], total_handed_over,
  // total_pending, currency }. cashBalance/cashHandoverStart/
  // cashHandoverStatus are still unbuilt/unconfirmed guesses.
  // CLIENT-REPORTED BUG (fixed): these four all had a redundant leading
  // "/driver" — baseUrl above ALREADY ends in "/api/driver", same as
  // every other path in this file (see orders/earnings/updateStatus
  // etc., none of which repeat "/driver"). That extra prefix was
  // producing .../api/driver/driver/cash-handovers instead of the
  // correct .../api/driver/cash-handovers.
  static const String cashBalance        = '/cash-balance';             // GET -> {amount} — UNCONFIRMED
  static const String cashHandovers      = '/cash-handovers';           // GET — CONFIRMED, see CashHandoverSummary.fromJson
  static const String cashHandoverStart  = '/cash-handover/start';      // POST -> {handover_id, token or qr_url, code, amount, expires_at} — UNCONFIRMED
  static const String cashHandoverStatus = '/cash-handover/{id}/status';// GET -> {status: pending|confirmed|expired} — UNCONFIRMED

  // ── Path helpers ──────────────────────────────────────────────
  static String path(String template, Map<String, String> params) {
    var out = template;
    params.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }
}
