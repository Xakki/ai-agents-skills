#!/usr/bin/env python3
"""The skill tree follows the naming registry and native invocation policy."""
from pathlib import Path
import json
import re
import subprocess
import sys
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]


class SkillRegistry(unittest.TestCase):
    def test_registry_check_is_clean(self):
        done = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/skills_registry.py'), 'check'],
                              capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_skills_are_single_level(self):
        for skill in (ROOT / 'skills').rglob('SKILL.md'):
            self.assertEqual(skill.parent.parent, ROOT / 'skills', skill)

    def test_model_invocation_follows_registry_tier(self):
        always = set(json.loads((ROOT / 'skills-registry.json').read_text())['tiers']['always'])
        self.assertTrue(always)
        for skill in (ROOT / 'skills').glob('*/SKILL.md'):
            text = skill.read_text(encoding='utf-8')
            match = re.match(r'\A---\n(.*?)\n---\n', text, re.S)
            self.assertIsNotNone(match, skill)
            frontmatter = yaml.safe_load(match.group(1))
            self.assertIs(frontmatter.get('disable-model-invocation', False), skill.parent.name not in always, skill)
            policy = yaml.safe_load((skill.parent / 'agents/openai.yaml').read_text())
            self.assertIs(policy['policy']['allow_implicit_invocation'], skill.parent.name in always, skill)

    def test_catalog_respects_native_invocation_boundaries(self):
        catalog = (ROOT / 'skills/agent-skill-find/references/catalog.md').read_text()
        finder = (ROOT / 'skills/agent-skill-find/SKILL.md').read_text()
        self.assertIn('ask the user to invoke', catalog)
        self.assertIn('do not reproduce a blocked skill', catalog)
        self.assertIn('read its `SKILL.md` to reproduce the blocked invocation', finder)
        self.assertNotIn('../<name>/SKILL.md', catalog + finder)

    def test_automatic_skills_do_not_link_to_manual_skill_entrypoints(self):
        always = set(json.loads((ROOT / 'skills-registry.json').read_text())['tiers']['always'])
        for name in always:
            for doc in (ROOT / 'skills' / name).rglob('*.md'):
                for target in re.findall(r'\.\./([^/]+)/SKILL\.md', doc.read_text()):
                    self.assertIn(target, always, f'{doc}: {target}')


if __name__ == '__main__':
    unittest.main()
