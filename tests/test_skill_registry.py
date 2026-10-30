#!/usr/bin/env python3
"""The skill tree follows the naming registry: names, descriptions, autoload tiers and the catalog."""
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SkillRegistry(unittest.TestCase):
    def test_registry_check_is_clean(self):
        done = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/skills_registry.py'), 'check'],
                              capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_skills_are_single_level(self):
        for skill in (ROOT / 'skills').rglob('SKILL.md'):
            self.assertEqual(skill.parent.parent, ROOT / 'skills', skill)


if __name__ == '__main__':
    unittest.main()
