# renovate-config — local agent notes only

Static engineering and delivery standards load from the active Skills runtime
([SylphxAI/skills](https://github.com/SylphxAI/skills) is binding instruction
SSOT). Doctrine and Mission Control are retired historical lineage and must not
be loaded as current instruction authority.

Local product truth: `PROJECT.md` when present, plus the repo delivery
declaration. Keep this file product-local; do not restate company-wide
standards here.

## Local rules

- Prefer the narrowest affected check before full workspace runs.
- Report layers honestly: source · CI · merge · deploy · live proof (do not collapse).
- Never commit secrets, customer data, tokens, or private keys.
