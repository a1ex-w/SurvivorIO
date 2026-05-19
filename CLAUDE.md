# Code Quality Checklist

Before writing any new code, check the codebase for existing systems that already solve or partially solve the problem. Extend or reuse before creating something new.

Before finalizing ANY code, silently run through these four questions. If any answer is no, fix it before responding.

1. **Evergreen?** Can this be reused by future devs or AI agents without rewriting it? Prefer general systems over one-off solutions.
2. **Documented?** Would another dev or AI agent understand the purpose, usage, and contract of this code without asking? Add comments where the WHY or HOW TO USE is non-obvious.
3. **Automatic?** Does the system require as little manual wiring as possible? New items, scenes, or features should work with the system for free — not require the dev to remember extra steps.
4. **Safe?** Are there any crashes, null access, timing issues, or game-breaking edge cases? Check node-ready timing, missing keys, server/client authority boundaries, and RPC targets.

# Comments and Commits

Every system, class, and non-trivial function must have a comment that answers three things for a future AI or dev reading it cold:
- **What it is** — one sentence on the purpose
- **How to use it** — concrete usage example or extension pattern
- **What to watch out for** — constraints, authority boundaries, timing requirements, or gotchas

Commit messages must describe what the system does and why it exists, not just what files changed. Another AI reading the git log should be able to reconstruct the intent without reading the diff.

# Pull Requests

Every PR must include a test plan with a checklist item for every new feature, system, or fix added. Each item must be specific enough that a tester knows exactly what to do and what to expect. Never leave test items unchecked unless they require infrastructure (e.g. live server) that can't be tested locally — in that case note why.

