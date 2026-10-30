# Yandex OAuth reference

For a requested Yandex OAuth or Metrika integration, identify the relevant resource, user account, application identity, authorization flow, permissions and current documented API. Use the provider's authoritative sources for supported scopes, request formats, token lifecycle and error meanings:

- [Metrika authorization](https://yandex.com/dev/metrika/en/intro/authorization)
- [Authorization-code URL](https://yandex.com/dev/id/doc/en/codes/code-url)
- [Refresh-token flow](https://yandex.com/dev/id/doc/en/tokens/refresh-client)
- [Metrika API errors](https://yandex.com/dev/metrika/en/intro/errors)

Provider documentation may change. Do not treat a status code, stored token or generic account login as proof of resource access. Investigate the documented response and the actual account and permissions through an authorized interface without disclosing credentials.

## Bundled helper

`scripts/yandex-oauth.sh` is a launcher for `yandex_oauth.py` (standard library, Python 3.8+).

- `authorize-url` reads `<OAUTH_PREFIX>_CLIENT_ID` from `ENV_FILE`, parses rather than sources it, and prints the public authorization URL. The default prefix is `OAUTH` and the default file `.env.local`. The client ID may contain only letters, digits, underscore or hyphen; duplicates fail closed.
- `printf '%s' "$CODE" | yandex-oauth.sh exchange` swaps an authorization code for tokens; a code given as an argument is refused.
- `yandex-oauth.sh refresh` uses the stored refresh token and stores a rotated one when the provider returns it.
- `yandex-oauth.sh check [COUNTER_ID]` sends the stored token to the Metrika counter endpoint (numeric ID) or `login.yandex.ru/info` and prints the HTTP status.
- Every secret-bearing command accepts `--dry-run`: it validates the key file and keys, then stops before any network or write.

Storage rules: the key file must be a regular file owned by the caller and not group/world-writable (a group/world-readable mode only warns). Operations take an exclusive `flock` on `<ENV_FILE>.lock`, so concurrent refreshes of a rotating token run one at a time. Only the token keys are replaced, in a temp file in the same directory with the original mode, flushed and renamed over the target (a symlinked `ENV_FILE` stays a symlink); comments and other keys are untouched. If the new tokens cannot be stored they are kept in a 0600 `.<name>.yandex-oauth-recovery-*` file beside the target and only its path is printed.

Limits: the lock protects only writers that use this helper, not editors or other tools; tokens issued by a successful call cannot be revoked by a later storage failure. Reload the consuming service yourself after a rotation.

Before a credential update, determine how the actual secure store handles access, rotation, concurrent writers and recovery; atomic replacement alone does not establish ownership. Verify how the consumer reloads changed values. Neither research nor configuration inspection authorizes a live token probe, credential replacement, job scheduling, service restart or notification.
