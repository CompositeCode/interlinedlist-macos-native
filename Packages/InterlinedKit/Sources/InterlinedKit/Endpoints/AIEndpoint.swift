import Foundation

/// Request builders for the **AI** endpoints (work-consolidation.md G15) — the
/// composer writing assistant, message/article series planning, AI list
/// templates, and AI documents.
///
/// The surface is a deliberate two-step: `suggest` runs the feature and returns
/// a **preview artifact** without persisting anything, and `generate` takes a
/// confirmed artifact back and persists it. The native UI mirrors that — a
/// preview sheet with an explicit Confirm — so a user is never billed for an
/// artifact they did not accept, and nothing is written behind their back.
///
/// **Gating:** AI is subscriber-only *and* needs the account to have supplied
/// its own provider key (OpenAI / Anthropic / Gemini) on the web Integrations
/// page. `status()` reports both, plus a daily quota, so the UI can explain a
/// refusal instead of failing opaquely.
///
/// Paths and request shapes verified live 2026-09-05 against the `.env` test
/// account, cross-read against the web client's own call sites:
/// - `GET /api/ai/status` → `{subscriber, providers, defaultModels, quota}`
/// - `POST /api/ai/suggest` `{feature, input, context?}` → `{artifact}`
/// - `POST /api/ai/generate` `{feature, artifact, …}` → `{created}`
///
/// The `feature` enum was mapped without spending quota: an unknown feature is
/// rejected with `"Unknown or missing feature."` before any model call, while a
/// known one with no input answers `"Input is required."`.
public enum AI {

    /// `GET /api/ai/status` — subscriber flag, configured providers, default
    /// models, and today's quota. Cheap enough to call before showing the
    /// assistant so the menu can be disabled with a reason.
    public static func status() -> Request<AIStatusDTO> {
        Request(method: .get, path: "/api/ai/status", auth: .bearer)
    }

    /// `POST /api/ai/suggest` — run a feature and return a preview artifact.
    /// **Costs the account a quota unit and a call against its own provider
    /// key**, so callers should gate on a real user action, never on appearance.
    public static func suggest(_ body: AISuggestRequest) -> Request<AISuggestResponse> {
        Request(method: .post, path: "/api/ai/suggest", body: .json(body), auth: .bearer)
    }

    /// `POST /api/ai/generate` — persist a previously previewed artifact.
    /// The artifact should be the one `suggest` returned, unedited.
    public static func generate(_ body: AIGenerateRequest) -> Request<AIGenerateResponse> {
        Request(method: .post, path: "/api/ai/generate", body: .json(body), auth: .bearer)
    }
}
