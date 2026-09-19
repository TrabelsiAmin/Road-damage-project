import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class ContractTests(unittest.TestCase):
    def test_all_agents_have_disjoint_expected_classes(self):
        manifest = json.loads((ROOT / 'config/model-bundles.json').read_text())
        agents = {item['name']: set(item['classes']) for item in manifest['agents']}
        self.assertEqual(agents['cracks'], {'D00', 'D10'})
        self.assertEqual(agents['pavement'], {'D20', 'D40'})
        self.assertEqual(agents['surface'], {'D50', 'D60', 'D90'})
        self.assertEqual(set().union(*agents.values()), {'D00', 'D10', 'D20', 'D40', 'D50', 'D60', 'D90'})

    def test_manifest_has_mobile_postprocess_contract(self):
        manifest = json.loads((ROOT / 'config/model-bundles.json').read_text())
        self.assertEqual(manifest['input']['width'], 640)
        self.assertEqual(manifest['input']['height'], 640)
        self.assertEqual(manifest['postprocess']['coordinateSpace'], 'normalized')
        self.assertGreater(manifest['postprocess']['confidenceThreshold'], 0)

if __name__ == '__main__':
    unittest.main()
