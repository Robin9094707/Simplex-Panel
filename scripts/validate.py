from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
for folder in ('Panel', 'Shared', 'PanelWidgets'):
    for path in (root / folder).rglob('*.swift'):
        text = path.read_text()
        assert not re.search(r'\b(?:AMPAPI|SuiteAPI|SuiteModel|isKinetic|AddonUpdateModel)\b', text), path
        assert not re.search(r'https?://[^"\s]*(?:modrinth|spiget|spigotmc|curseforge|kinetic)', text, re.I), path
        assert 'eu.simplexsmp.panel' not in text, path
        assert 'panel://' not in text, path
assert 'eu.simplexsmp.wing' in (root / 'project.yml').read_text()
print('Community isolation checks passed.')
