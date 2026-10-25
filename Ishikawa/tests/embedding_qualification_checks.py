from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path


class EmbeddingQualificationChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        test_file = Path(__file__).resolve()
        cls.ishikawa_root = test_file.parents[1]
        cls.phase_root = cls.ishikawa_root.parent
        cls.repo_root = cls.phase_root.parent
        helper_path = cls.phase_root / "scripts/qualify_chunk_embeddings.py"
        spec = importlib.util.spec_from_file_location("qualify_chunk_embeddings", helper_path)
        if spec is None or spec.loader is None:
            raise RuntimeError("helper import failed")
        cls.helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.helper)
        cls.candidate_path = (
            cls.repo_root
            / "local/artifacts/ishikawa/chunking"
            / "structural_chunk_candidates_20261019T214924Z.json"
        )
        cls.candidate_document = json.loads(cls.candidate_path.read_text(encoding="utf-8"))

    def refresh_candidate_set_digest(self, document):
        digest_input = copy.deepcopy(document)
        digest_input.pop("chunk_candidate_set_digest", None)
        document["chunk_candidate_set_digest"] = self.helper.domain_digest(
            "ishikawa.chunk-candidate-set.v1", digest_input
        )

    def test_accepted_candidates_validate(self):
        candidates = self.helper.validate_candidates(self.candidate_document)
        self.assertEqual(len(candidates), 125)
        self.assertEqual(len({item["chunk_id"] for item in candidates}), 125)

    def test_wrong_candidate_set_is_rejected(self):
        changed = copy.deepcopy(self.candidate_document)
        changed["chunk_candidate_set_digest"] = "0" * 64
        with self.assertRaisesRegex(self.helper.QualificationError, "contract_mismatch"):
            self.helper.validate_candidates(changed)

    def test_duplicate_chunk_identity_is_rejected(self):
        changed = copy.deepcopy(self.candidate_document)
        first = changed["documents"][0]["candidates"][0]
        changed["documents"][0]["candidates"].append(copy.deepcopy(first))
        self.refresh_candidate_set_digest(changed)
        with self.assertRaisesRegex(self.helper.QualificationError, "duplicate"):
            self.helper.validate_candidates(changed)

    def test_changed_retrieval_projection_is_rejected(self):
        changed = copy.deepcopy(self.candidate_document)
        changed["documents"][0]["candidates"][0]["retrieval_text"] += " changed"
        self.refresh_candidate_set_digest(changed)
        with self.assertRaisesRegex(self.helper.QualificationError, "projection_invalid"):
            self.helper.validate_candidates(changed)

    def test_document_prefix_is_exact(self):
        self.assertEqual(self.helper.DOCUMENT_PREFIX, "search_document: ")
        self.assertEqual(self.helper.EXPECTED_MAX_MODEL_LEN, 2048)
        self.assertEqual(self.helper.INITIAL_TARGET_TOKENS, 512)

    def test_embedding_tuple_is_exact(self):
        self.assertEqual(self.helper.EXPECTED_MODEL_ID, "nomic-ai/nomic-embed-text-v1.5")
        self.assertEqual(self.helper.EXPECTED_DIMENSION, 768)
        self.assertEqual(
            self.helper.EXPECTED_TOKENIZER_SHA256,
            "d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66",
        )

    def test_base_url_is_loopback_only(self):
        self.assertEqual(
            self.helper.validate_base_url("http://127.0.0.1:8001"),
            "http://127.0.0.1:8001",
        )
        with self.assertRaisesRegex(self.helper.QualificationError, "loopback"):
            self.helper.validate_base_url("http://192.0.2.1:8001")

    def test_domain_identities_are_deterministic(self):
        left = self.helper.domain_digest("test", {"b": 2, "a": 1})
        right = self.helper.domain_digest("test", {"a": 1, "b": 2})
        self.assertEqual(left, right)
        self.assertRegex(left, r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
