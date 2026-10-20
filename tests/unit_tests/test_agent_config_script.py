"""Behavioral coverage for .agents/scripts/link-agent-skills.sh.

The script maintains the agent-agnostic skill layout (see .agents/AGENTS.md):
canonical skills under .agents/skills/, per-harness directories holding
symlinks. These tests sandbox the layout, drive the script in sync and
check modes, and pin the behaviors an adversarial review flagged:

- committed symlinks are repaired/relinked when stale or missing
- dangling symlinks (canonical skill deleted) are pruned by sync and
  reported by --check
- byte-identical generated duplicates (the post-``openspec update`` state)
  are converted back to symlinks
- divergent duplicates are refused, never deleted
- an expansion scenario: a new workflow skill appears as real per-harness
  directories plus a canonical copy, and one sync run restores the layout
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / ".agents" / "scripts" / "link-agent-skills.sh"
TARGETS = (".claude/skills", ".opencode/skills", ".omp/skills")


@pytest.fixture()
def sandbox(tmp_path: Path) -> Path:
    """A fake repo root with one canonical skill, empty targets, the script.

    The script resolves the repo root from its own location, so a copy is
    placed inside the sandbox; the tests exercise the exact bytes of the
    committed script without touching the real repo.
    """
    skills = tmp_path / ".agents" / "skills"
    skills.mkdir(parents=True)
    (skills / "my-skill").mkdir()
    (skills / "my-skill" / "SKILL.md").write_text("skill body\n")
    scripts = tmp_path / ".agents" / "scripts"
    scripts.mkdir()
    shutil.copy(SCRIPT, scripts / "link-agent-skills.sh")
    for target in TARGETS:
        (tmp_path / target).mkdir(parents=True)
    return tmp_path


def run_sync(sandbox: Path, check: bool = False) -> subprocess.CompletedProcess[str]:
    args = ["bash", str(sandbox / ".agents" / "scripts" / "link-agent-skills.sh")]
    if check:
        args.append("--check")
    return subprocess.run(
        args,
        cwd=sandbox,
        capture_output=True,
        text=True,
        env={"PATH": "/usr/bin:/bin", "HOME": str(sandbox)},
    )


def make_skill(skills_dir: Path, name: str, body: str = "skill body\n") -> None:
    (skills_dir / name).mkdir()
    (skills_dir / name / "SKILL.md").write_text(body)


class TestSync:
    def test_links_canonical_skills_into_every_target(self, sandbox: Path) -> None:
        result = run_sync(sandbox)
        assert result.returncode == 0
        for target in TARGETS:
            link = sandbox / target / "my-skill"
            assert link.is_symlink()
            assert link.resolve() == (sandbox / ".agents" / "skills" / "my-skill")
        # Idempotent: a second run changes nothing and stays clean.
        assert run_sync(sandbox).returncode == 0
        assert run_sync(sandbox, check=True).returncode == 0

    def test_missing_target_dir_is_created(self, sandbox: Path) -> None:
        shutil.rmtree(sandbox / ".claude" / "skills")
        assert run_sync(sandbox).returncode == 0
        assert (sandbox / ".claude" / "skills" / "my-skill").is_symlink()

    def test_wrong_symlink_target_is_relinked(self, sandbox: Path) -> None:
        run_sync(sandbox)
        link = sandbox / ".claude" / "skills" / "my-skill"
        link.unlink()
        link.symlink_to("somewhere-else")
        assert run_sync(sandbox).returncode == 0
        assert link.resolve() == (sandbox / ".agents" / "skills" / "my-skill")


class TestPruning:
    def test_dangling_symlink_is_pruned_by_sync(self, sandbox: Path) -> None:
        run_sync(sandbox)
        (sandbox / ".agents" / "skills" / "my-skill").mkdir(  # type: ignore[call-overload]
            exist_ok=True
        )
        shutil.rmtree(sandbox / ".agents" / "skills" / "my-skill")
        link = sandbox / ".claude" / "skills" / "my-skill"
        assert not link.exists() and link.is_symlink()  # dangling
        assert run_sync(sandbox).returncode == 0
        assert not link.is_symlink() and not link.exists()

    def test_check_reports_dangling_symlink(self, sandbox: Path) -> None:
        run_sync(sandbox)
        shutil.rmtree(sandbox / ".agents" / "skills" / "my-skill")
        result = run_sync(sandbox, check=True)
        assert result.returncode == 1
        assert "stale symlink" in result.stderr


class TestDuplicateConversion:
    def test_byte_identical_duplicate_is_converted(self, sandbox: Path) -> None:
        run_sync(sandbox)
        link = sandbox / ".opencode" / "skills" / "my-skill"
        link.unlink()
        duplicate = sandbox / ".opencode" / "skills" / "my-skill"
        duplicate.mkdir()
        (duplicate / "SKILL.md").write_text("skill body\n")
        assert run_sync(sandbox).returncode == 0
        assert duplicate.is_symlink()

    def test_generated_per_harness_duplicates_are_converted(
        self, sandbox: Path
    ) -> None:
        """Real OpenSpec output: per-harness renderings differ in spellings.

        Uses the committed fixtures (generated by driving the openspec CLI
        1.14.3 generator: templates/workflows/{verify,onboard} rendered per
        tool). Codex content becomes the canonical copy; each harness dir
        receives its own tool's rendering — which is exactly the state
        `openspec init`/`update` leaves behind when the expanded profile
        adds the verify/onboard workflows.
        """
        fixture = Path(__file__).parent / "fixtures" / "openspec_generated"
        for skill in ("openspec-verify-change", "openspec-onboard"):
            shutil.copytree(
                fixture / "codex" / skill, sandbox / ".agents" / "skills" / skill
            )
        for tool, target in (
            ("claude", ".claude/skills"),
            ("opencode", ".opencode/skills"),
            ("oh-my-pi", ".omp/skills"),
        ):
            for skill in ("openspec-verify-change", "openspec-onboard"):
                shutil.copytree(fixture / tool / skill, sandbox / target / skill)

        assert run_sync(sandbox, check=True).returncode == 1  # drift detected
        assert run_sync(sandbox).returncode == 0
        assert run_sync(sandbox, check=True).returncode == 0
        for target in TARGETS:
            for skill in ("openspec-verify-change", "openspec-onboard"):
                assert (sandbox / target / skill).is_symlink()

    def test_check_reports_unconverted_duplicate(self, sandbox: Path) -> None:
        run_sync(sandbox)
        link = sandbox / ".opencode" / "skills" / "my-skill"
        link.unlink()
        duplicate = sandbox / ".opencode" / "skills" / "my-skill"
        duplicate.mkdir()
        (duplicate / "SKILL.md").write_text("skill body\n")
        result = run_sync(sandbox, check=True)
        assert result.returncode == 1
        assert "unconverted duplicate" in result.stderr

    def test_divergent_duplicate_is_refused_not_deleted(self, sandbox: Path) -> None:
        run_sync(sandbox)
        link = sandbox / ".omp" / "skills" / "my-skill"
        link.unlink()
        divergent = sandbox / ".omp" / "skills" / "my-skill"
        divergent.mkdir()
        (divergent / "SKILL.md").write_text("hand-edited content\n")
        result = run_sync(sandbox)
        assert result.returncode == 1
        assert "differs" in result.stderr
        assert divergent.is_dir()  # untouched
        assert (divergent / "SKILL.md").read_text() == "hand-edited content\n"

    def test_generated_duplicate_with_real_edit_is_refused(self, sandbox: Path) -> None:
        """A genuine edit beyond the invocation spellings stays divergent."""
        fixture = Path(__file__).parent / "fixtures" / "openspec_generated"
        shutil.copytree(
            fixture / "codex" / "openspec-verify-change",
            sandbox / ".agents" / "skills" / "openspec-verify-change",
        )
        edited = sandbox / ".claude" / "skills" / "openspec-verify-change"
        shutil.copytree(fixture / "claude" / "openspec-verify-change", edited)
        body = (edited / "SKILL.md").read_text()
        (edited / "SKILL.md").write_text(
            body.replace(
                "Verify that an implementation",
                "LOCAL EDIT Verify that an implementation",
                1,
            )
        )
        result = run_sync(sandbox)
        assert result.returncode == 1
        assert "differs" in result.stderr
        assert edited.is_dir()


class TestWorkflowExpansion:
    def test_new_workflow_restores_layout_in_one_run(self, sandbox: Path) -> None:
        """openspec init/update regenerates real dirs; one sync restores."""
        run_sync(sandbox)
        # Simulate `openspec update` enabling an extra workflow: a new
        # canonical skill appears AND every harness dir gets a real copy.
        skills = sandbox / ".agents" / "skills"
        make_skill(skills, "openspec-verify", "verify body\n")
        for target in TARGETS:
            copy = sandbox / target / "openspec-verify"
            copy.mkdir()
            (copy / "SKILL.md").write_text("verify body\n")
        # The update also rewrote an existing harness dir with a real copy.
        stale_link = sandbox / ".claude" / "skills" / "my-skill"
        stale_link.unlink()
        real = sandbox / ".claude" / "skills" / "my-skill"
        real.mkdir()
        (real / "SKILL.md").write_text("skill body\n")

        assert run_sync(sandbox, check=True).returncode == 1  # drift detected
        assert run_sync(sandbox).returncode == 0
        assert run_sync(sandbox, check=True).returncode == 0
        for target in TARGETS:
            for name in ("my-skill", "openspec-verify"):
                assert (sandbox / target / name).is_symlink()

    def test_missing_symlink_fails_check(self, sandbox: Path) -> None:
        result = run_sync(sandbox, check=True)
        assert result.returncode == 1
        assert "missing (expected symlink" in result.stderr
