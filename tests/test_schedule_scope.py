"""Runtime regressions for scoped autonomous Kanban scheduling."""

from __future__ import annotations

import hashlib
import os
import re
import subprocess
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
CREATE_SCOPE = ROOT / "scripts" / "create-task-scope.sh"
SELECT_NEXT = ROOT / "scripts" / "select-next-task.sh"
CHAIN_NEXT = ROOT / "scripts" / "chain-next-task.sh"
RUNNER = ROOT / "scripts" / "run-claude-task.sh"


def _run(command: list[str], *, env: dict[str, str], check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, env=env, check=check)


def _job_command(runner: str, task_file: str, scope_id: str) -> str:
    result = subprocess.run(
        [
            "bash",
            "-c",
            'source "$1"; task_scope_job_command "$2" "$3" "$4"',
            "test",
            str(ROOT / "scripts" / "task-scope.sh"),
            runner,
            task_file,
            scope_id,
        ],
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def _repo(tmp_path: Path) -> Path:
    repo = tmp_path / "project"
    todo = repo / ".agents" / "kanban" / "todo"
    for stage in ("todo", "progress", "test", "ready", "done"):
        (repo / ".agents" / "kanban" / stage).mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "--initial-branch=main", str(repo)], check=True, capture_output=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "-c",
            "user.name=Schedule Test",
            "-c",
            "user.email=schedule-test@example.invalid",
            "commit",
            "--allow-empty",
            "-m",
            "fixture",
        ],
        check=True,
        capture_output=True,
    )
    return repo


def _card(repo: Path, name: str, body: str = "") -> Path:
    path = repo / ".agents" / "kanban" / "todo" / name
    path.write_text(body, encoding="utf-8")
    return path


def _env(tmp_path: Path, **extra: str) -> dict[str, str]:
    env = os.environ.copy()
    home = tmp_path / "home"
    home.mkdir(parents=True, exist_ok=True)
    env["HOME"] = str(home)
    env["TMPDIR"] = str(tmp_path / "var-tmp")
    Path(env["TMPDIR"]).mkdir(parents=True, exist_ok=True)
    env.update(extra)
    return env


def _create_scope(
    tmp_path: Path,
    repo: Path,
    cards: list[Path],
    env: dict[str, str] | None = None,
) -> tuple[str, dict[str, str]]:
    env = _env(tmp_path) if env is None else env
    command = [
        str(CREATE_SCOPE),
        "--repo",
        str(repo),
        "--approved",
        "--approval-source",
        "explicit-user",
    ]
    for card in cards:
        command.extend(["--card", str(card)])
    result = _run(command, env=env)
    assert result.returncode == 0, result.stderr
    match = re.search(r"^scope-id=([a-f0-9]{64})$", result.stdout, re.MULTILINE)
    assert match, result.stdout
    # Disposable fixture: commit the synthetic cards so clean-start checks test
    # the intended branch, not untracked setup artifacts.
    subprocess.run(['git', '-C', str(repo), 'add', '--', '.agents'], check=True, capture_output=True)
    subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-m', 'synthetic cards'], check=True, capture_output=True)
    return match.group(1), env


def test_scope_creation_requires_explicit_approval_and_exact_todo_cards(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    card = _card(repo, "CNV-10-first.md")
    env = _env(tmp_path)

    denied = _run(
        [str(CREATE_SCOPE), "--repo", str(repo), "--approval-source", "explicit-user", "--card", str(card)],
        env=env,
    )

    assert denied.returncode != 0
    assert "--approved" in denied.stderr
    assert not list((Path(env["HOME"]) / ".local/state/claude-auto-runs").rglob("*.manifest"))

    outside = repo / ".agents" / "kanban" / "ready" / "CNV-11-not-todo.md"
    outside.write_text("not a todo card\n", encoding="utf-8")
    rejected = _run(
        [
            str(CREATE_SCOPE),
            "--repo",
            str(repo),
            "--approved",
            "--approval-source",
            "explicit-user",
            "--card",
            str(outside),
        ],
        env=env,
    )

    assert rejected.returncode != 0
    assert "todo" in rejected.stderr.lower()

    escaped = repo / ".agents" / "kanban" / "todo" / "CNV-12-escape.md"
    external_card = tmp_path / "outside-card.md"
    external_card.write_text("outside todo root\n", encoding="utf-8")
    escaped.symlink_to(external_card)
    symlink_rejected = _run(
        [str(CREATE_SCOPE), "--repo", str(repo), "--approved", "--approval-source", "explicit-user", "--card", str(escaped)],
        env=env,
    )
    assert symlink_rejected.returncode != 0
    assert "todo" in symlink_rejected.stderr.lower()


def test_scope_selector_uses_only_approved_cards_in_recorded_order(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    outside = _card(repo, "CNV-01-outside.md")
    second = _card(repo, "CNV-20-second.md")
    first = _card(repo, "CNV-10-first.md")
    scope_id, env = _create_scope(tmp_path, repo, [second, first])

    result = _run(
        [str(SELECT_NEXT), str(repo), str(Path(env["HOME"]) / ".local/state/claude-auto-runs/project/.parked"), "", scope_id],
        env=env,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == second.name
    assert outside.name not in result.stdout


def test_scope_selector_skips_blocked_and_finished_cards_without_falling_back(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    blocked = _card(repo, "CNV-10-blocked.md", "Depends on K-9\n")
    allowed = _card(repo, "CNV-20-allowed.md")
    following = _card(repo, "CNV-30-following.md")
    _card(repo, "CNV-30-outside.md")
    scope_id, env = _create_scope(tmp_path, repo, [blocked, allowed, following])
    parked = Path(env["HOME"]) / ".local/state/claude-auto-runs/project/.parked"
    parked.mkdir(parents=True)
    (parked / "K-9.md").write_text("parked\n", encoding="utf-8")

    result = _run([str(SELECT_NEXT), str(repo), str(parked), "", scope_id], env=env)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == allowed.name

    after_allowed = _run([str(SELECT_NEXT), str(repo), str(parked), allowed.name, scope_id], env=env)
    assert after_allowed.returncode == 0, after_allowed.stderr
    assert after_allowed.stdout.strip() == following.name

    (repo / ".agents" / "kanban" / "todo" / allowed.name).unlink()
    (repo / ".agents" / "kanban" / "todo" / following.name).unlink()
    (repo / ".agents" / "kanban" / "todo" / blocked.name).unlink()
    (repo / ".agents" / "kanban" / "todo" / "CNV-30-outside.md").write_text("outside\n", encoding="utf-8")
    exhausted = _run([str(SELECT_NEXT), str(repo), str(parked), "", scope_id], env=env)

    assert exhausted.returncode == 0, exhausted.stderr
    assert exhausted.stdout.strip() == "none"


def test_scope_selector_never_returns_to_an_earlier_card_after_progress(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    finished = _card(repo, "CNV-05-finished.md")
    blocked = _card(repo, "CNV-10-blocked.md", "Depends on K-9\n")
    later = _card(repo, "CNV-20-later.md")
    scope_id, env = _create_scope(tmp_path, repo, [finished, blocked, later])
    (repo / ".agents" / "kanban" / "todo" / finished.name).unlink()
    (repo / ".agents" / "kanban" / "ready" / finished.name).write_text("ready\n", encoding="utf-8")
    parked = Path(env["HOME"]) / ".local/state/claude-auto-runs/project/.parked"
    parked.mkdir(parents=True)
    parked_entry = parked / "K-9.md"
    parked_entry.write_text("parked\n", encoding="utf-8")

    first = _run([str(SELECT_NEXT), str(repo), str(parked), finished.name, scope_id], env=env)
    assert first.returncode == 0, first.stderr
    assert first.stdout.strip() == later.name

    parked_entry.unlink()
    after_later = _run([str(SELECT_NEXT), str(repo), str(parked), later.name, scope_id], env=env)

    assert after_later.returncode == 0, after_later.stderr
    assert after_later.stdout.strip() == "none"


def test_chain_helper_enqueues_only_selector_result_with_same_scope(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    finished = _card(repo, "CNV-10-finished.md")
    next_card = _card(repo, "CNV-20-next.md")
    _card(repo, "CNV-01-outside.md")
    scope_id, env = _create_scope(tmp_path, repo, [finished, next_card])
    (repo / ".agents" / "kanban" / "todo" / finished.name).unlink()
    (repo / ".agents" / "kanban" / "ready" / finished.name).write_text("ready\n", encoding="utf-8")

    fake_bin = Path(env["HOME"]) / ".local/bin"
    fake_bin.mkdir(parents=True)
    at_log = tmp_path / "at-input"
    env["FAKE_AT_LOG"] = str(at_log)
    (fake_bin / "systemctl").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    (fake_bin / "systemctl").chmod(0o755)
    (fake_bin / "at").write_text(
        "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$FAKE_AT_LOG\"\n"
        "cat >> \"$FAKE_AT_LOG\"\nprintf 'job 1 at test\\n'\n",
        encoding="utf-8",
    )
    (fake_bin / "at").chmod(0o755)
    env["PATH"] = f"{fake_bin}:{env['PATH']}"

    subprocess.run(['git', '-C', str(repo), 'add', '--', '.agents'], check=True, capture_output=True)
    subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'synthetic move'], check=True, capture_output=True)
    baseline = tmp_path / "baseline"
    status = subprocess.run(["git", "-C", str(repo), "status", "--porcelain"], check=True, capture_output=True, text=True)
    baseline.write_text(status.stdout, encoding="utf-8")
    parked = Path(env["HOME"]) / ".local/state/claude-auto-runs/project/.parked"

    result = _run(
        [str(CHAIN_NEXT), str(repo), str(parked), finished.name, scope_id, str(baseline)],
        env=env,
    )

    assert result.returncode == 0, result.stderr
    assert f"AUTO-RUN-NEXT: {next_card.name}" in result.stdout
    queued = at_log.read_text(encoding="utf-8")
    assert next_card.name in queued
    assert scope_id in queued

    queued_before_dirty = at_log.read_text(encoding="utf-8")
    (repo / "unrelated-uncommitted.txt").write_text("new dirty path\n", encoding="utf-8")
    dirty_result = _run(
        [str(CHAIN_NEXT), str(repo), str(parked), finished.name, scope_id, str(baseline)],
        env=env,
    )
    assert dirty_result.returncode == 0, dirty_result.stderr
    assert "uncommitted repository changes" in dirty_result.stderr
    assert "AUTO-RUN-NEXT: none" in dirty_result.stdout
    assert at_log.read_text(encoding="utf-8") == queued_before_dirty


def test_tampered_scope_manifest_fails_closed(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    card = _card(repo, "CNV-10-first.md")
    scope_id, env = _create_scope(tmp_path, repo, [card])
    manifest = Path(env["HOME"]) / ".local/state/claude-auto-runs/project/scopes" / f"{scope_id}.manifest"
    manifest.chmod(0o644)
    manifest.write_text(manifest.read_text(encoding="utf-8") + "card=CNV-99-outside.md\n", encoding="utf-8")

    result = _run([str(SELECT_NEXT), str(repo), "", "", scope_id], env=env)

    assert result.returncode != 0
    assert any(word in result.stderr.lower() for word in ("hash", "digest", "integrity"))


def test_scope_creator_rejects_symlinked_scopes_directory(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    card = _card(repo, "CNV-10-first.md")
    env = _env(tmp_path)
    log_dir = Path(env["HOME"]) / ".local/state/claude-auto-runs/project"
    log_dir.mkdir(parents=True)
    outside_scopes = tmp_path / "outside-scopes"
    outside_scopes.mkdir()
    (log_dir / "scopes").symlink_to(outside_scopes, target_is_directory=True)

    result = _run(
        [str(CREATE_SCOPE), "--repo", str(repo), "--approved", "--approval-source", "explicit-user", "--card", str(card)],
        env=env,
    )

    assert result.returncode != 0
    assert not list(outside_scopes.iterdir())


def test_scope_loader_rejects_symlinked_scopes_directory(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    card = _card(repo, "CNV-10-first.md")
    scope_id, env = _create_scope(tmp_path, repo, [card])
    log_dir = Path(env["HOME"]) / ".local/state/claude-auto-runs/project"
    scopes = log_dir / "scopes"
    manifest = scopes / f"{scope_id}.manifest"
    outside_scopes = tmp_path / "outside-scopes"
    outside_scopes.mkdir()
    (outside_scopes / manifest.name).write_bytes(manifest.read_bytes())
    scopes.rename(log_dir / "scopes-original")
    scopes.symlink_to(outside_scopes, target_is_directory=True)

    result = _run([str(SELECT_NEXT), str(repo), "", "", scope_id], env=env)

    assert result.returncode != 0
    assert "scope" in result.stderr.lower()


def test_scope_loader_rejects_wrong_repository_and_base_branch(tmp_path: Path) -> None:
    repo = _repo(tmp_path / "source")
    card = _card(repo, "CNV-10-first.md")
    scope_id, env = _create_scope(tmp_path, repo, [card])
    other_repo = _repo(tmp_path / "other")
    _card(other_repo, card.name)

    wrong_repo = _run([str(SELECT_NEXT), str(other_repo), "", "", scope_id], env=env)
    assert wrong_repo.returncode != 0
    assert "repository" in wrong_repo.stderr.lower()

    subprocess.run(["git", "-C", str(repo), "checkout", "-b", "other-base"], check=True, capture_output=True)
    wrong_base = _run([str(SELECT_NEXT), str(repo), "", "", scope_id], env=env)
    assert wrong_base.returncode != 0
    assert "base branch" in wrong_base.stderr.lower()


def test_scope_job_match_requires_exact_card_and_scope_arguments() -> None:
    scope_file = str(ROOT / "scripts" / "task-scope.sh")
    task_file = "/repo/.agents/kanban/todo/CNV-20-next.md"
    runner = str(RUNNER)
    scope_id = "a" * 64

    def helper(name: str, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", "-c", 'source "$1"; shift; "$@"', "test", scope_file, name, *args],
            text=True,
            capture_output=True,
        )

    expected = helper("task_scope_job_command", runner, task_file, scope_id)
    assert expected.returncode == 0, expected.stderr
    exact_line = expected.stdout.strip()
    wrong_card = helper("task_scope_job_command", runner, task_file + "-suffix", scope_id)
    assert wrong_card.returncode == 0, wrong_card.stderr
    wrong_scope = helper("task_scope_job_command", runner, task_file, scope_id + "f")
    assert wrong_scope.returncode == 0, wrong_scope.stderr

    exact_job = f"header\n{exact_line}\n"
    false_card_job = f"header\n{wrong_card.stdout.strip()}\n"
    false_scope_job = f"header\n{wrong_scope.stdout.strip()}\n"
    assert helper("task_scope_job_matches", exact_job, exact_line).returncode == 0
    assert helper("task_scope_job_matches", false_card_job, exact_line).returncode != 0
    todo_dir = "/repo/.agents/kanban/todo"
    card_name = Path(task_file).name
    assert helper("task_scope_job_scope_matches", exact_job, runner, scope_id, todo_dir, card_name).returncode == 0
    assert helper("task_scope_job_scope_matches", false_scope_job, runner, scope_id, todo_dir, card_name).returncode != 0


def _run_inner_with_fake_job(
    tmp_path: Path,
    repo: Path,
    card: Path,
    scope_id: str,
    env: dict[str, str],
    jsonl: str,
    at_command: str,
    lock_symlink_target: Path | None = None,
) -> tuple[subprocess.CompletedProcess[str], Path]:
    script_dir = tmp_path / "inner-scripts"
    script_dir.mkdir()
    inner_copy = script_dir / "run-claude-task-inner.sh"
    inner_copy.write_bytes((ROOT / "scripts" / "run-claude-task-inner.sh").read_bytes())
    inner_copy.chmod(0o755)
    (script_dir / "task-scope.sh").write_bytes((ROOT / "scripts" / "task-scope.sh").read_bytes())
    (script_dir / "summarize-task-usage.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    (script_dir / "summarize-task-usage.sh").chmod(0o755)

    fake_bin = Path(env["HOME"]) / "fake-bin"
    fake_bin.mkdir()
    fake_claude = fake_bin / "claude"
    fake_claude.write_text(
        r'''#!/bin/sh
session=''
while [ $# -gt 0 ]; do
  if [ "$1" = '--session-id' ]; then session=$2; shift 2; else shift; fi
done
project_path=$(printf '%s' "$REPO_PATH" | tr '/' '-')
mkdir -p "$HOME/.claude/projects/$project_path"
printf '%s\n' "$FAKE_JSONL" > "$HOME/.claude/projects/$project_path/$session.jsonl"
''',
        encoding="utf-8",
    )
    fake_claude.chmod(0o755)
    fake_atq = fake_bin / "atq"
    fake_atq.write_text("#!/bin/sh\nprintf '7\\n'\n", encoding="utf-8")
    fake_atq.chmod(0o755)
    fake_at = fake_bin / "at"
    fake_at.write_text("#!/bin/sh\ncat \"$FAKE_AT_SCRIPT\"\n", encoding="utf-8")
    fake_at.chmod(0o755)
    atrm_log = tmp_path / "atrm.log"
    fake_atrm = fake_bin / "atrm"
    fake_atrm.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$FAKE_ATRM_LOG\"\n", encoding="utf-8")
    fake_atrm.chmod(0o755)

    at_script = tmp_path / "queued-at-script"
    at_script.write_text(f"#!/bin/sh\n{at_command}\n", encoding="utf-8")
    if lock_symlink_target is not None:
        lock_file = Path(env["HOME"]) / ".local/state/claude-auto-runs/project/scopes" / f"{hashlib.sha256(('repo:' + str(repo.resolve())).encode()).hexdigest()}.lock"
        lock_file.symlink_to(lock_symlink_target)
    child_env = env.copy()
    child_env["PATH"] = f"{fake_bin}:{child_env['PATH']}"
    child_env["REPO_PATH"] = str(repo)
    child_env["FAKE_JSONL"] = jsonl
    child_env["FAKE_AT_SCRIPT"] = str(at_script)
    child_env["FAKE_ATRM_LOG"] = str(atrm_log)
    child_env["PYTHONDONTWRITEBYTECODE"] = "1"
    result = subprocess.run(
        [str(inner_copy), str(card), scope_id],
        input="\n",
        text=True,
        capture_output=True,
        env=child_env,
        timeout=10,
    )
    return result, atrm_log


def test_inner_does_not_accept_card_basename_substring_as_queued_job(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    current = _card(repo, "CNV-10-current.md")
    next_card = _card(repo, "CNV-20-next.md")
    scope_id, env = _create_scope(tmp_path, repo, [current, next_card])
    runner = str(tmp_path / "inner-scripts" / "run-claude-task.sh")
    wrong_card = str(repo / ".agents" / "kanban" / "todo" / f"{next_card.name}-suffix")
    at_command = _job_command(runner, wrong_card, scope_id)

    result, _ = _run_inner_with_fake_job(
        tmp_path,
        repo,
        current,
        scope_id,
        env,
        f"AUTO-RUN-RESULT: ok:\nAUTO-RUN-NEXT: {next_card.name}",
        at_command,
    )

    assert result.returncode == 0, result.stderr
    assert "no matching at-job is queued" in result.stdout
    assert "verified scoped at-job" not in result.stdout


def test_inner_does_not_cancel_job_for_scope_id_substring(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    current = _card(repo, "CNV-10-current.md")
    next_card = _card(repo, "CNV-20-next.md")
    scope_id, env = _create_scope(tmp_path, repo, [current, next_card])
    runner = str(tmp_path / "inner-scripts" / "run-claude-task.sh")
    task_file = str(repo / ".agents" / "kanban" / "todo" / next_card.name)
    wrong_scope_id = f"{scope_id}f"
    at_command = _job_command(runner, task_file, wrong_scope_id)

    result, atrm_log = _run_inner_with_fake_job(
        tmp_path,
        repo,
        current,
        scope_id,
        env,
        "AUTO-RUN-RESULT: skip:\nAUTO-RUN-NEXT: none",
        at_command,
    )

    assert result.returncode == 0, result.stderr
    assert "no continuation" in result.stdout
    assert not atrm_log.exists()


def test_inner_does_not_cancel_modified_command_in_scope(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    current = _card(repo, "CNV-10-current.md")
    next_card = _card(repo, "CNV-20-next.md")
    scope_id, env = _create_scope(tmp_path, repo, [current, next_card])
    runner = str(tmp_path / "inner-scripts" / "run-claude-task.sh")
    task_file = str(repo / ".agents" / "kanban" / "todo" / next_card.name)
    at_command = _job_command(runner, task_file, scope_id).replace(
        f" '{scope_id}'",
        f" '--unexpected-argument' '{scope_id}'",
    )

    result, atrm_log = _run_inner_with_fake_job(
        tmp_path,
        repo,
        current,
        scope_id,
        env,
        "AUTO-RUN-RESULT: skip:\nAUTO-RUN-NEXT: none",
        at_command,
    )

    assert result.returncode == 0, result.stderr
    assert "no continuation" in result.stdout
    assert not atrm_log.exists()


def test_inner_rejects_lock_symlink_without_truncating_target(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    current = _card(repo, "CNV-10-current.md")
    scope_id, env = _create_scope(tmp_path, repo, [current])
    protected = tmp_path / "protected-lock-target"
    protected.write_text("keep this content\n", encoding="utf-8")

    result, _ = _run_inner_with_fake_job(
        tmp_path,
        repo,
        current,
        scope_id,
        env,
        "AUTO-RUN-RESULT: skip:\nAUTO-RUN-NEXT: none",
        "",
        lock_symlink_target=protected,
    )

    assert result.returncode != 0
    assert "symlink" in result.stderr.lower() or "symlink" in result.stdout.lower()
    assert protected.read_text(encoding="utf-8") == "keep this content\n"
    assert not (Path(env["HOME"]) / "claude.finished").exists()


def test_runner_rejects_missing_or_out_of_scope_id_before_tmux(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    allowed = _card(repo, "CNV-10-allowed.md")
    outside = _card(repo, "CNV-20-outside.md")
    scope_id, env = _create_scope(tmp_path, repo, [allowed])
    fake_bin = Path(env["HOME"]) / ".local/bin"
    fake_bin.mkdir(parents=True)
    marker = tmp_path / "tmux-called"
    env["FAKE_TMUX_LOG"] = str(marker)
    fake_tmux = fake_bin / "tmux"
    fake_tmux.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$FAKE_TMUX_LOG\"\n", encoding="utf-8")
    fake_tmux.chmod(0o755)

    missing = _run([str(RUNNER), str(allowed)], env=env)
    assert missing.returncode != 0
    assert not marker.exists()

    denied = _run([str(RUNNER), str(outside), scope_id], env=env)
    assert denied.returncode != 0
    assert not marker.exists()

    accepted = _run([str(RUNNER), str(allowed), scope_id], env=env)
    assert accepted.returncode == 0, accepted.stderr
    assert marker.exists()
    assert scope_id in marker.read_text(encoding="utf-8")


def test_inner_releases_run_lock_before_waiting_for_window_close(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    card = _card(repo, "CNV-10-first.md")
    scope_id, env = _create_scope(tmp_path, repo, [card])
    script_dir = tmp_path / "scripts"
    script_dir.mkdir()
    inner_copy = script_dir / "run-claude-task-inner.sh"
    inner_copy.write_bytes((ROOT / "scripts" / "run-claude-task-inner.sh").read_bytes())
    inner_copy.chmod(0o755)
    task_scope_copy = script_dir / "task-scope.sh"
    task_scope_copy.write_bytes((ROOT / "scripts" / "task-scope.sh").read_bytes())
    (script_dir / "summarize-task-usage.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    (script_dir / "summarize-task-usage.sh").chmod(0o755)

    fake_bin = Path(env["HOME"]) / "bin"
    fake_bin.mkdir(parents=True)
    fake_claude = fake_bin / "claude"
    fake_claude.write_text(
        r'''#!/bin/sh
session=''
while [ $# -gt 0 ]; do
  if [ "$1" = '--session-id' ]; then session=$2; shift 2; else shift; fi
done
project_path=$(printf '%s' "$REPO_PATH" | tr '/' '-')
mkdir -p "$HOME/.claude/projects/$project_path"
printf '%s\n' 'AUTO-RUN-RESULT: skip:' 'AUTO-RUN-NEXT: none' > "$HOME/.claude/projects/$project_path/$session.jsonl"
touch "$HOME/claude.finished"
''',
        encoding="utf-8",
    )
    fake_claude.chmod(0o755)
    (fake_bin / "atq").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    (fake_bin / "atq").chmod(0o755)
    env["PATH"] = f"{fake_bin}:{env['PATH']}"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env["REPO_PATH"] = str(repo)

    process = subprocess.Popen(
        [str(inner_copy), str(card), scope_id],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    deadline = time.monotonic() + 10
    finished_marker = Path(env["HOME"]) / "claude.finished"
    lock_file = Path(env["HOME"]) / ".local/state/claude-auto-runs/project/scopes" / f"{hashlib.sha256(('repo:' + str(repo.resolve())).encode()).hexdigest()}.lock"
    probe = None
    while time.monotonic() < deadline and process.poll() is None:
        if finished_marker.exists():
            probe = subprocess.run(["flock", "-n", str(lock_file), "-c", "true"], capture_output=True)
            if probe.returncode == 0:
                break
        time.sleep(0.05)

    waiting_for_close = process.poll() is None
    output, _ = process.communicate("\n", timeout=5)

    assert waiting_for_close, output
    assert probe is not None and probe.returncode == 0, "the completed run must release its lock before waiting for Enter"
    assert process.returncode == 0, output


def test_scope_creator_rejects_symlink_manifest_without_chmod_target(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    card = _card(repo, "CNV-10-first.md")
    env = _env(tmp_path)
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    fake_date = fake_bin / "date"
    fake_date.write_text("#!/bin/sh\nprintf '%s\\n' '2026-01-02T03:04:05Z'\n", encoding="utf-8")
    fake_date.chmod(0o755)
    env["PATH"] = f"{fake_bin}:{env['PATH']}"

    scope_id, _ = _create_scope(tmp_path, repo, [card], env=env)
    scope_dir = Path(env["HOME"]) / ".local/state/claude-auto-runs/project/scopes"
    manifest = scope_dir / f"{scope_id}.manifest"
    protected = tmp_path / "protected-state"
    protected.write_bytes(manifest.read_bytes())
    protected.chmod(0o600)
    manifest.unlink()
    manifest.symlink_to(protected)

    result = _run(
        [
            str(ROOT / "scripts" / "create-task-scope.sh"),
            "--repo",
            str(repo),
            "--approved",
            "--approval-source",
            "explicit-user",
            "--card",
            str(card),
        ],
        env=env,
    )

    assert result.returncode != 0
    assert protected.stat().st_mode & 0o777 == 0o600
