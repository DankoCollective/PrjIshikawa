from __future__ import annotations

import unittest

from ishikawa.retrieval import (
    FusedCandidate,
    LaneCandidate,
    RetrievalContractError,
    balanced_document_shortlist,
    collapse_retrieval_groups,
    decomposed_candidate_pool,
    decompose_retrieval_query,
    exact_term_lookup,
    exact_document_page_lookup,
    declared_identifier_parameters,
    extract_explicit_page,
    extract_structured_terms,
    expand_authoritative_candidates,
    lexical_search,
    reciprocal_rank_fusion,
    score_calibrated_global_rerank,
    select_ranked_relevance_candidates,
    vector_search,
    uses_calibrated_body_route,
)


class RecordingConnection:
    def __init__(self, responses):
        self.responses = list(responses)
        self.executions = []

    def execute(self, sql, parameters):
        self.executions.append((sql, parameters))
        return self

    def fetchall(self):
        return self.responses.pop(0)


def candidate(chunk: str, lane: str, rank: int, *, document: str = "doc") -> LaneCandidate:
    return LaneCandidate(
        chunk_id=chunk,
        document_id=document,
        document_version_id=f"{document}-version",
        document_key=f"policy.{document}",
        lane=lane,
        rank=rank,
        raw_score=1.0 / rank,
        exact_reason="chunk_id_match" if lane == "exact" else None,
        retrieval_variant="strict" if lane == "lexical" else None,
    )


class RetrievalFusionTests(unittest.TestCase):
    def test_literal_query_decomposition_is_bounded_and_noninventive(self) -> None:
        self.assertEqual(
            decompose_retrieval_query(
                "What control applies; and when is escalation required?"
            ),
            ("What control applies", "when is escalation required"),
        )

    def test_calibrated_route_excludes_metadata_relationship_and_page_intents(self) -> None:
        self.assertTrue(
            uses_calibrated_body_route(
                "Who is accountable for the request, and what evidence is required?",
                page_routed=False,
                complete_structure_requested=False,
            )
        )
        self.assertFalse(
            uses_calibrated_body_route(
                "Which department owns it and what is its effective date?",
                page_routed=False,
                complete_structure_requested=False,
            )
        )
        self.assertFalse(
            uses_calibrated_body_route(
                "Which references and review trigger are specified?",
                page_routed=False,
                complete_structure_requested=False,
            )
        )
        self.assertEqual(
            decompose_retrieval_query("What policy applies?"),
            ("What policy applies?",),
        )

    def test_balanced_shortlist_preserves_both_primary_lanes(self) -> None:
        lexical = tuple(
            candidate(f"l{index}", "lexical", index, document=f"lex-{index}")
            for index in range(1, 4)
        )
        vector = tuple(
            candidate(f"v{index}", "vector", index, document=f"vec-{index}")
            for index in range(1, 4)
        )
        self.assertEqual(
            balanced_document_shortlist((), lexical, vector, depth_per_lane=3),
            (
                "policy.lex-1", "policy.vec-1", "policy.lex-2",
                "policy.vec-2", "policy.lex-3", "policy.vec-3",
            ),
        )

    def test_decomposed_pool_can_introduce_a_shortlisted_passage(self) -> None:
        baseline_lane = (candidate("baseline", "vector", 1),)
        baseline = reciprocal_rank_fusion({"vector": baseline_lane})
        expanded = candidate("expanded", "vector", 1, document="expanded")
        result = decomposed_candidate_pool(
            baseline,
            ({"lexical": (), "vector": (expanded,)},),
            rrf_constant=60,
            baseline_weight=2,
            best_facet_weight=1,
            facet_coverage_weight=1,
        )
        self.assertEqual({item.chunk_id for item in result}, {"baseline", "expanded"})

    def test_calibrated_rerank_uses_frozen_raw_score_weights(self) -> None:
        low = FusedCandidate(
            "low", "doc-low", "version-low", "policy.low", 1.0, False, (),
            structural_path=("I. Purpose",),
        )
        high = FusedCandidate(
            "high", "doc-high", "version-high", "policy.high", 0.5, False, (),
            structural_path=("II. Required Control",),
        )
        lexical = (
            LaneCandidate("low", "doc-low", "version-low", "policy.low", "lexical", 1, 1.0,
                          retrieval_variant="strict"),
            LaneCandidate("high", "doc-high", "version-high", "policy.high", "lexical", 2, 0.5,
                          retrieval_variant="strict"),
        )
        vector = (
            LaneCandidate("high", "doc-high", "version-high", "policy.high", "vector", 1, 0.9),
            LaneCandidate("low", "doc-low", "version-low", "policy.low", "vector", 2, 0.1),
        )
        result = score_calibrated_global_rerank(
            (low, high), lexical, vector,
            ({"lexical": lexical, "vector": vector},),
            "What required control applies?",
        )
        self.assertEqual([item.chunk_id for item in result], ["high", "low"])

    def test_rrf_deduplicates_one_chunk_across_lanes(self) -> None:
        result = reciprocal_rank_fusion(
            {
                "lexical": (candidate("a", "lexical", 1),),
                "vector": (candidate("a", "vector", 2),),
            }
        )
        self.assertEqual([item.chunk_id for item in result], ["a"])
        self.assertEqual([item.lane for item in result[0].evidence], ["lexical", "vector"])

    def test_exact_candidate_has_deterministic_priority(self) -> None:
        result = reciprocal_rank_fusion(
            {
                "exact": (candidate("exact", "exact", 1),),
                "lexical": (candidate("other", "lexical", 1),),
                "vector": (candidate("other", "vector", 1),),
            }
        )
        self.assertEqual(result[0].chunk_id, "exact")
        self.assertTrue(result[0].exact_priority)

    def test_exact_atom_accepts_richer_structural_group_metadata(self) -> None:
        exact = candidate("same", "exact", 1)
        lexical = LaneCandidate(
            chunk_id="same",
            document_id="doc",
            document_version_id="doc-version",
            document_key="policy.doc",
            lane="lexical",
            rank=1,
            raw_score=1.0,
            retrieval_variant="strict",
            retrieval_group_id="section-page-group",
            authoritative_chunk_ids=("same",),
        )
        result = reciprocal_rank_fusion({"exact": (exact,), "lexical": (lexical,)})
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].retrieval_group_id, "section-page-group")
        self.assertTrue(result[0].exact_priority)

    def test_configured_weights_change_rrf_contributions(self) -> None:
        result = reciprocal_rank_fusion(
            {
                "lexical": (candidate("lexical", "lexical", 1),),
                "vector": (candidate("vector", "vector", 2),),
            },
            lane_weights={"exact": 1, "lexical": 1, "vector": 4},
        )
        self.assertEqual([item.chunk_id for item in result], ["vector", "lexical"])

    def test_invalid_lane_weights_are_rejected(self) -> None:
        invalid_weights = (
            {"exact": 1, "lexical": 1},
            {"exact": 1, "lexical": 1, "vector": 0},
            {"exact": 1, "lexical": 1, "vector": True},
        )
        for weights in invalid_weights:
            with self.subTest(weights=weights):
                with self.assertRaises(RetrievalContractError):
                    reciprocal_rank_fusion({}, lane_weights=weights)

    def test_equal_scores_tie_break_by_chunk_identity(self) -> None:
        result = reciprocal_rank_fusion(
            {"lexical": (candidate("b", "lexical", 1), candidate("a", "lexical", 1))}
        )
        self.assertEqual([item.chunk_id for item in result], ["a", "b"])

    def test_distinct_chunks_from_same_document_remain(self) -> None:
        result = reciprocal_rank_fusion(
            {"vector": (candidate("a", "vector", 1), candidate("b", "vector", 2))}
        )
        self.assertEqual(len(result), 2)

    def test_lane_duplicate_is_rejected(self) -> None:
        with self.assertRaises(RetrievalContractError):
            reciprocal_rank_fusion(
                {"lexical": (candidate("a", "lexical", 1), candidate("a", "lexical", 2))}
            )

    def test_lane_mismatch_is_rejected(self) -> None:
        with self.assertRaises(RetrievalContractError):
            reciprocal_rank_fusion({"lexical": (candidate("a", "vector", 1),)})

    def test_unknown_lane_is_rejected(self) -> None:
        with self.assertRaises(RetrievalContractError):
            reciprocal_rank_fusion({"semantic": ()})

    def test_invalid_rrf_constant_is_rejected(self) -> None:
        with self.assertRaises(RetrievalContractError):
            reciprocal_rank_fusion({}, rrf_constant=0)

    def test_structural_group_collapse_keeps_highest_ranked_candidate(self) -> None:
        first = FusedCandidate(
            "representative",
            "doc",
            "version",
            "policy.doc",
            0.5,
            False,
            (),
            retrieval_group_id="group",
            authoritative_chunk_ids=("atomic-a", "atomic-b"),
            retrieval_scoring_only=True,
        )
        duplicate = FusedCandidate(
            "atomic-a", "doc", "version", "policy.doc", 0.4, False, (),
            retrieval_group_id="group",
            authoritative_chunk_ids=("atomic-a",),
        )
        self.assertEqual(collapse_retrieval_groups((first, duplicate)), (first,))

    def test_exact_group_winner_retains_representative_atomic_envelope(self) -> None:
        exact = FusedCandidate(
            "atomic-b", "doc", "version", "policy.doc", 0.7, True, (),
            retrieval_group_id="group",
            authoritative_chunk_ids=("atomic-b",),
        )
        representative = FusedCandidate(
            "representative",
            "doc",
            "version",
            "policy.doc",
            0.5,
            False,
            (),
            retrieval_group_id="group",
            authoritative_chunk_ids=("atomic-a", "atomic-b", "atomic-c"),
            retrieval_scoring_only=True,
        )
        collapsed = collapse_retrieval_groups((exact, representative))
        self.assertEqual(len(collapsed), 1)
        self.assertEqual(collapsed[0].chunk_id, "atomic-b")
        self.assertEqual(
            collapsed[0].authoritative_chunk_ids,
            ("atomic-a", "atomic-b", "atomic-c"),
        )

    def test_structural_group_cannot_cross_document_identities(self) -> None:
        first = FusedCandidate(
            "a", "doc-a", "version-a", "policy.a", 0.5, False, (),
            retrieval_group_id="group",
        )
        conflicting = FusedCandidate(
            "b", "doc-b", "version-b", "policy.b", 0.4, False, (),
            retrieval_group_id="group",
        )
        with self.assertRaisesRegex(RetrievalContractError, "conflicting"):
            collapse_retrieval_groups((first, conflicting))

    def test_representative_expands_to_ordered_atomic_evidence(self) -> None:
        representative = FusedCandidate(
            "representative",
            "doc",
            "version",
            "policy.doc",
            0.5,
            False,
            (),
            retrieval_group_id="group",
            authoritative_chunk_ids=("atomic-a", "atomic-b"),
            retrieval_scoring_only=True,
        )
        expanded = expand_authoritative_candidates((representative,))
        self.assertEqual([item.chunk_id for item in expanded], ["atomic-a", "atomic-b"])
        self.assertTrue(all(not item.retrieval_scoring_only for item in expanded))

    def test_relevance_depth_keeps_one_atom_per_ranked_structural_result(self) -> None:
        candidates = tuple(
            FusedCandidate(
                f"representative-{index}",
                "doc",
                "version",
                "policy.doc",
                1.0 / index,
                False,
                (),
                retrieval_group_id=f"group-{index}",
                authoritative_chunk_ids=(f"atomic-{index}-a", f"atomic-{index}-b"),
                retrieval_scoring_only=True,
            )
            for index in range(1, 5)
        )
        selected = select_ranked_relevance_candidates(candidates, depth=3)
        self.assertEqual(
            [item.chunk_id for item in selected],
            ["atomic-1-a", "atomic-2-a", "atomic-3-a"],
        )
        self.assertEqual(
            [item.authoritative_chunk_ids for item in selected],
            [
                ("atomic-1-a", "atomic-1-b"),
                ("atomic-2-a", "atomic-2-b"),
                ("atomic-3-a", "atomic-3-b"),
            ],
        )
        self.assertTrue(all(not item.retrieval_scoring_only for item in selected))


class VectorBoundaryTests(unittest.TestCase):
    def test_wrong_vector_dimension_is_rejected_before_database_use(self) -> None:
        with self.assertRaisesRegex(RetrievalContractError, "768"):
            vector_search(object(), [0.0] * 767, "a" * 64)

    def test_malformed_embedding_space_is_rejected_before_database_use(self) -> None:
        with self.assertRaisesRegex(RetrievalContractError, "SHA-256"):
            vector_search(object(), [0.0] * 768, "not-a-digest")

    def test_candidate_representation_vector_route_uses_retrieval_view(self) -> None:
        row = (
            "representative", "document", "version", "policy.a", 0.9,
            "group", ["atomic-a"], True, True, ["I. Purpose"],
        )
        connection = RecordingConnection([[row]])
        result = vector_search(
            connection,
            [0.0] * 768,
            "a" * 64,
            use_candidate_representation=True,
        )
        self.assertEqual(result[0].authoritative_chunk_ids, ("atomic-a",))
        sql, parameters = connection.executions[0]
        self.assertIn("active_retrieval_embeddings", sql)
        self.assertIn("active_retrieval_candidates", sql)
        self.assertEqual(parameters[2:4], (True, True))


class StructuredExactTermTests(unittest.TestCase):
    def test_extracts_identifier_and_document_number_in_query_order(self) -> None:
        self.assertEqual(
            extract_structured_terms("Compare REQ-0001 with 99 TST 2002."),
            ("REQ-0001", "99 TST 2002"),
        )

    def test_ordinary_language_produces_no_structured_term(self) -> None:
        self.assertEqual(extract_structured_terms("How is an exception decided?"), ())

    def test_duplicate_terms_are_folded(self) -> None:
        self.assertEqual(
            extract_structured_terms("REQ-0001 and REQ-0001"),
            ("REQ-0001",),
        )

    def test_exact_lookup_rejects_unstructured_text_before_database_use(self) -> None:
        with self.assertRaisesRegex(RetrievalContractError, "unsupported shape"):
            exact_term_lookup(object(), "ordinary words")

    def test_extracts_only_one_unambiguous_explicit_page(self) -> None:
        self.assertEqual(extract_explicit_page("Show page 7 of 99 TST 2002"), 7)
        self.assertIsNone(extract_explicit_page("Compare page 1 with page 2"))
        self.assertIsNone(extract_explicit_page("Show 99 TST 2002"))

    def test_document_page_lookup_returns_citable_exact_candidate(self) -> None:
        connection = RecordingConnection([[('a' * 64, 'b' * 64, 'c' * 64, 'policy.a', 1.0)]])
        result = exact_document_page_lookup(connection, "99 TST 2002", 1)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].exact_reason, "document_page_match")
        sql, parameters = connection.executions[0]
        self.assertIn("active_citations", sql)
        self.assertIn("relevant_excerpt", sql)
        self.assertIn("policy number:", sql)
        self.assertIn("form no.", sql)
        self.assertNotIn("lower(btrim(retrieval_text))", sql)
        self.assertEqual(
            parameters,
            (*(("99 TST 2002",) * 5), 1, 1, 1),
        )

    def test_declared_identifier_parameters_are_bounded_and_complete(self) -> None:
        self.assertEqual(
            declared_identifier_parameters("99 TST 2005"),
            ("99 TST 2005",) * 5,
        )
        with self.assertRaisesRegex(RetrievalContractError, "unsupported shape"):
            declared_identifier_parameters("ordinary document title")


class LexicalFallbackTests(unittest.TestCase):
    def test_strict_results_do_not_run_the_or_fallback(self) -> None:
        connection = RecordingConnection([[('a', 'b', 'c', 'policy.a', 0.5)]])
        result = lexical_search(connection, "temporary exception")
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].retrieval_variant, "strict")
        self.assertEqual(len(connection.executions), 1)

    def test_empty_strict_search_runs_native_or_fallback(self) -> None:
        connection = RecordingConnection([[], [('a', 'b', 'c', 'policy.a', 0.25)]])
        result = lexical_search(connection, "temporary controlled exception")
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].retrieval_variant, "or_fallback")
        self.assertEqual(len(connection.executions), 2)
        self.assertIn("lexical.or_fallback", connection.executions[1][0])

    def test_candidate_representation_metadata_is_preserved(self) -> None:
        row = (
            "representative", "document", "version", "policy.a", 0.75,
            "group", ["atomic-a", "atomic-b"], True, True, ["I. Purpose"],
        )
        connection = RecordingConnection([[row]])
        result = lexical_search(
            connection,
            "temporary controlled access",
            use_candidate_representation=True,
        )
        self.assertEqual(result[0].retrieval_group_id, "group")
        self.assertEqual(result[0].authoritative_chunk_ids, ("atomic-a", "atomic-b"))
        self.assertTrue(result[0].retrieval_scoring_only)
        sql, parameters = connection.executions[0]
        self.assertIn("active_retrieval_candidates", sql)
        self.assertEqual(parameters[2:4], (True, True))


if __name__ == "__main__":
    unittest.main()
