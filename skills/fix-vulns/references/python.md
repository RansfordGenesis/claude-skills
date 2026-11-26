# Python (pip, uv, Poetry, Pipenv, PDM, pip-tools)

Read this when the repo has `requirements*.txt`, `pyproject.toml`, `uv.lock`, `poetry.lock`, `Pipfile.lock`, `pdm.lock`, `setup.py` or `setup.cfg`.

## Identify the tool and what is actually deployed

| Files present | Tool | Source of truth |
|---|---|---|
| `uv.lock` | uv | `uv.lock` |
| `poetry.lock` | Poetry | `poetry.lock` |
| `Pipfile.lock` | Pipenv | `Pipfile.lock` |
| `pdm.lock` | PDM | `pdm.lock` |
| `requirements.in` + `requirements.txt` | pip-tools | the compiled `requirements.txt` (edit `.in`, recompile) |
| `requirements.txt` only | pip | the file, if fully pinned; otherwise whatever pip resolved at deploy time |
| `pyproject.toml` only | pip / build backend | nothing reproducible; resolved at install time |

- Use the tool the lockfile implies. Running `pip install -U` in a uv or Poetry project changes nothing that is committed.
- **Unpinned requirements** (`fastapi>=0.100`, `boto3==1.*`, bare names): the audit resolves them to today's versions, which may not be what production runs. Find what is deployed: the Docker image (`docker run <image> pip freeze`), the Lambda layer or package, or the host's build log. Say in the report which one you audited.
- A requirements file that pins only direct packages hides the transitive ones. `scripts/collect_alerts.sh` resolves every file before auditing so the whole tree is checked.
- **Python version**: read `requires-python`, `.python-version`, `runtime.txt`, the Dockerfile `FROM`, the Lambda/Cloud Run runtime, and CI's `python-version`. Patched releases often drop old Pythons (a fix may need 3.9+ or 3.10+). Resolve for the deployed interpreter, e.g. `uv pip compile --python-version 3.11`.
- **Platform**: many packages ship compiled wheels (`cryptography`, `pydantic-core`, `numpy`, `psycopg[binary]`, `lxml`). If the target is Linux (Docker, Lambda, CI) and you are on macOS, check that a `manylinux` wheel exists for the new version and the deployed architecture (x86_64 vs arm64/Graviton): `pip download <pkg>==<ver> --platform manylinux2014_x86_64 --only-binary=:all: --no-deps -d /tmp/wheels`. For uv, `uv.lock` records wheels for all platforms; check the entry includes the Linux ones.

## Auditing

- `pip-audit` (PyPA, uses the PyPI and OSV advisory databases). Run without installing it permanently: `uvx pip-audit` or `pipx run pip-audit`.
  - Pinned file: `pip-audit -r requirements.txt --no-deps --disable-pip` (audits exactly what is listed).
  - uv: `uv export --frozen --format requirements-txt --no-hashes --no-emit-project --all-groups > /tmp/req.txt`, then the pinned form above.
  - Poetry: `osv-scanner scan source --lockfile poetry.lock`, or `poetry export -f requirements.txt --without-hashes --with dev` (Poetry 2 needs the `poetry-plugin-export` plugin) piped to `pip-audit`.
  - Unpinned file or bare `pyproject.toml`: resolve first (`uv pip compile requirements.txt -o /tmp/req.txt`, or `uv pip compile pyproject.toml --all-extras`), then audit the pinned result.
- `pip-audit` reports the PYSEC/GHSA id, aliases (CVE), and `fix_versions`. "none" means no patched release exists yet.
- Trace who pulls in a transitive package: `uv tree --invert --package <pkg>`, `poetry show --tree` / `poetry show --why <pkg>`, `pipdeptree -r -p <pkg>` (in an environment with the deps installed), `pipenv graph --reverse`.

## Fixing

Keep the existing pin style: `==` stays `==`, `~=` stays `~=`, a `>=` floor gets raised rather than turned into an exact pin.

| Tool | Direct dependency | Transitive dependency |
|---|---|---|
| uv | edit the constraint in `pyproject.toml`, then `uv lock --upgrade-package <pkg>` | `uv lock --upgrade-package <pkg>` if the parent's range allows it; else `[tool.uv] constraint-dependencies = ["<pkg>>=x.y.z"]` (narrow); `override-dependencies` only as a last resort |
| Poetry | `poetry add "<pkg>@^x.y.z"` or edit and `poetry lock` (Poetry 1.x: `poetry lock --no-update`) | `poetry update <pkg>`; if the parent blocks it, add the package as an explicit dependency with the patched floor and a comment |
| Pipenv | edit `Pipfile`, `pipenv lock` / `pipenv upgrade <pkg>` | `pipenv update <pkg>` |
| PDM | `pdm update <pkg>` / `pdm add` | `pdm update --unconstrained <pkg>` only if the parent allows it |
| pip-tools | raise the floor in `requirements.in`, `pip-compile --upgrade-package <pkg>` | `pip-compile --upgrade-package <pkg>` |
| plain pip | edit the line in `requirements.txt` | add it to a constraints file (`-c constraints.txt`) or pin it in `requirements.txt` with a comment naming the parent |

- Never run a blanket `uv lock --upgrade`, `poetry update` with no arguments, or `pip install -U -r`: they upgrade unrelated packages. Upgrade only the named packages, and compare the lockfile before and after (`git diff uv.lock` and similar) to confirm nothing else moved.
- Preview where the tool allows it: `uv lock --upgrade-package <pkg> --dry-run`, `poetry update <pkg> --dry-run`.
- Packages that move together: `fastapi` with `starlette` (FastAPI pins a Starlette range, so a Starlette fix usually means a FastAPI bump); `django` with its contrib packages and `djangorestframework`; `boto3` with `botocore` and `s3transfer`; `pydantic` with `pydantic-core` (never pin `pydantic-core` yourself); `celery` with `kombu`; `requests` with `urllib3`; `aws-cdk-lib` with `constructs`.
- Packages with no fix: some advisories are "wontfix" (`ecdsa` Minerva timing, `python-jose`). The mitigation is usually replacing the library (e.g. `python-jose` → `PyJWT` or `joserfc`; `ecdsa` → `cryptography`). Report it as an option for the user rather than swapping a library unasked.

## Reachability hints

- Web frameworks (Django, Flask, FastAPI/Starlette, aiohttp, Tornado): request parsing, multipart/form uploads, static file serving, redirects and host headers are reachable by any visitor.
- Parsers (`pyyaml` with `load`, `lxml`, `xmltodict`, `pyasn1`, `pillow`, `pdf` libraries): reachable if they parse uploads or third-party data.
- Crypto and auth (`cryptography`, `pyjwt`, `python-jose`, `ecdsa`, `certifi`): check what is actually used. `certifi` updates are root-store changes; take them.
- Infrastructure as code (`aws-cdk-lib`, `pulumi`): runs on developer machines and CI, not in production, but it shapes what gets deployed (e.g. IAM policies, bucket settings), so read the advisory.
- Test and dev tooling (`pytest`, `black`, `ruff`, `mypy`, `moto`): dev only.
- `pip`, `setuptools` and `wheel` in the deployed image are worth updating too; they are often flagged and are not in the lockfile.

## Validation specifics

- Create a throwaway environment rather than touching the user's: `uv sync --frozen` (uv), `poetry install --sync` in a fresh venv, or `python -m venv /tmp/venv && /tmp/venv/bin/pip install -r requirements.txt`.
- Run what the project has: `pytest`, `ruff check` / `flake8`, `mypy` / `pyright`, `python -m compileall -q .` as a cheap syntax check, Django `python manage.py check` (and `--deploy` if relevant) and `python manage.py makemigrations --check --dry-run`.
- Conflicts: `uv pip check` or `pip check` in the environment.
- Runtime: import the app (`python -c "import app.main"`), then start it (`uvicorn app.main:app`, `gunicorn`, `flask run`, `manage.py runserver`) and hit a few routes, including any that use the upgraded package. For AWS Lambda, invoke the handler locally with a sample event, or `sam local invoke` if the repo uses SAM.
