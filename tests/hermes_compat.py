"""Check the installed Hermes host in an isolated profile; never start its gateway.

Run with Hermes's Python: hermes_compat.py --source <Hermes installation directory>
"""

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(Path(args.source).resolve(strict=True)))
    from hermes_constants import reset_hermes_home_override, set_hermes_home_override

    # Retain evidence; no cleanup can accidentally target a real profile.
    scratch = Path(tempfile.mkdtemp(prefix="hermes-assistant-compat-"))
    token = set_hermes_home_override(scratch)
    try:
        skill = scratch / "skills/productivity/personal-assistant"
        shutil.copytree(Path(__file__).parents[1] / "personal-assistant", skill)
        from tools.skills_tool import skill_view
        from tools.cronjob_tools import CRONJOB_SCHEMA
        from cron.jobs import create_job, list_jobs, pause_job, remove_job, update_job

        loaded = json.loads(skill_view("personal-assistant"))
        assert not loaded.get("error"), loaded
        text = json.dumps(loaded)
        assert "references/setup.md" in text
        for mode in ("setup", "run", "update"):
            reference = json.loads(
                skill_view("personal-assistant", f"references/{mode}.md")
            )
            assert not reference.get("error"), reference
        fields = CRONJOB_SCHEMA["parameters"]["properties"]
        assert all(
            key in fields
            for key in ("skills", "workdir", "deliver", "attach_to_session")
        )
        created = []
        for mode, schedule in (("morning", "0 8 * * *"), ("monitor", "0 9-19 * * *")):
            job = create_job(
                prompt=f"Isolated compatibility fixture: {mode}",
                schedule=schedule,
                name=f"fixture-{mode}",
                skills=["personal-assistant"],
                workdir=str(scratch),
                deliver="local",
                attach_to_session=True,
            )
            created.append(job["id"])
        for job_id in created:
            assert update_job(job_id, {"prompt": "Updated isolated fixture"})
            assert pause_job(job_id)
        assert len(list_jobs(include_disabled=True)) == 2
        for job_id in created:
            assert remove_job(job_id)
        assert not list_jobs(include_disabled=True)
        print(
            f"Hermes skill load, references, cron create/update/pause/remove passed: {scratch}"
        )
    finally:
        reset_hermes_home_override(token)


if __name__ == "__main__":
    main()
