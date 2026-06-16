# Architecture Checklist

Use this checklist before finalizing code changes.

- Responsibilities are separated by layer: UI, domain, networking, persistence.
- Protocol boundaries exist for dependencies that require mocking or substitution.
- No view type owns business rules that should live in domain services.
- Networking logic is isolated from rendering logic.
- Concurrency is explicit and safe (async/await with clear task ownership).
- Error paths are handled and surfaced predictably.
- New code avoids speculative abstractions.
- Naming is clear and behavior-focused.
