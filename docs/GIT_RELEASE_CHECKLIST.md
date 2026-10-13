# Git release and server synchronization checklist

## 1. Prepare the repository

- Commit source code, tests, migrations, lockfiles, CI workflows, deployment templates,
  sanitized examples, and documentation.
- Exclude local caches, generated output, databases, user uploads, build packages,
  credentials, signing files, and unlicensed model weights.
- Review every staged file with `git diff --cached --stat` and `git diff --cached`.

## 2. Validate locally

Run the focused checks for each changed application, then run the repository CI checks.
Do not place real production credentials in test commands or logs.

## 3. Create the remote safely

1. Create a private empty repository without generated README or license files.
2. Add it as `origin` using SSH or a credential helper; never embed a token in the URL.
3. Push the initial reviewed commit to `main`.
4. Enable branch protection, pull-request review, secret scanning, and dependency alerts.
5. Make the repository public only after a separate license and privacy review.

This repository currently has no root license file. Keep the remote private until the
owner selects a license and verifies rights for vendored code and media assets.

## 4. Synchronize to a server

Prefer CI/CD or a read-only deploy key. On the server, clone into a release directory,
create `.env.cloud` directly on the server with restrictive permissions, and deploy with
`docker compose -f docker-compose.cloud.yml --env-file .env.cloud up -d --build`.

Do not copy `.git`, local databases, development `.env` files, or workstation output to
the server. Back up production volumes separately before migrations or upgrades.

## 5. Update and roll back

- Deploy an immutable tag or commit SHA rather than an unreviewed working tree.
- Record the deployed SHA and database migration version.
- Back up persistent data before `alembic upgrade head`.
- Roll back application containers to the previous tag; restore the database only from
  a tested backup and only when the migration strategy requires it.
