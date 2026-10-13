# Security policy

## Secrets and private data

- Never commit `.env`, `.env.cloud`, database files, signing keys, certificates,
  access tokens, production exports, user uploads, or server backups.
- Keep only sanitized placeholders in `.env.example` files.
- Store production secrets in the server environment or a dedicated secret manager.
- Rotate a credential immediately if it is ever committed, even if the commit is later
  removed from Git history.

## Before publishing

1. Review `git diff --cached` and `git status --short`.
2. Run a secret scanner over the full Git history.
3. Confirm licenses for vendored code, fonts, images, datasets, and model weights.
4. Use a private remote until the repository content and history have been approved.

## Reporting

Report security issues privately to the repository owner. Do not include credentials,
personal data, or production database contents in a public issue.
