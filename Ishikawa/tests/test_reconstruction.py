from __future__ import annotations

import json
import unittest
from dataclasses import replace
from pathlib import Path

from ishikawa.canonical import domain_digest
from ishikawa.reconstruction import (
    CompleteProcedureTarget,
    EvidenceCandidate,
    EvidenceCitation,
    ReconstructionContractError,
    ReconstructionPolicy,
    assemble_evidence,
    deduplicate_candidates,
    reconstruct_complete_procedure,
    validate_reconstruction_profile,
)
from ishikawa.yaml_loader import load_restricted_yaml


def identity(label: str) -> str:
    return domain_digest("ishikawa.reconstruction-test.v1", label)


def count_words(text: str) -> int:
    return len(text.split())


def policy(**changes) -> ReconstructionPolicy:
    values = {
        "tokenizer_model": "qualified-tokenizer-pending",
        "tokenizer_identity": identity("tokenizer"),
        "temperature": 1.0,
        "top_p": 0.95,
        "top_k": 64,
        "total_context_tokens": 100,
        "instruction_token_limit": 20,
        "conversation_token_limit": 20,
        "evidence_token_limit": 40,
        "answer_token_reserve": 20,
        "generation_prompt_targets": (30, 50, 70),
        "generation_optional_group_limit": 6,
        "normal_per_document_limit": 2,
        "explicit_document_limit": 5,
    }
    values.update(changes)
    return ReconstructionPolicy(**values)


def candidate(
    label: str,
    *,
    text: str | None = None,
    rank: int = 1,
    ordinal: int = 0,
    document: str = "alpha",
    path: tuple[str, ...] = ("I. Procedure",),
    origin: str = "direct",
    citation_label: str | None = None,
    group: str | None = None,
) -> EvidenceCandidate:
    content = text or f"Step {label}"
    citation = EvidenceCitation(
        citation_id=identity(citation_label or f"citation:{label}:{document}"),
        document_id=identity(f"document:{document}"),
        document_version_id=identity(f"version:{document}"),
        document_key=f"procedure.{document}",
        page_start=ordinal + 1,
        page_end=ordinal + 1,
        structural_path=path,
    )
    return EvidenceCandidate(
        chunk_id=identity(f"chunk:{label}"),
        retrieval_text_digest=domain_digest("ishikawa.retrieval-text.v1", {"retrieval_text": content}),
        retrieval_text=content,
        projection_kind="list_item",
        ordinal=ordinal,
        retrieval_rank=rank,
        origin=origin,
        inclusion_reason="direct_retrieval" if origin == "direct" else "explicit_reference_one_hop",
        citations=(citation,),
        retrieval_group_id=group,
        relationship_provenance=() if origin == "direct" else (identity(f"edge:{label}"),),
    )


class ReconstructionPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profile_path = Path(__file__).resolve().parents[1] / "config/templates/reconstruction_profile.yaml"
        cls.profile_value = load_restricted_yaml(cls.profile_path, label="reconstruction profile")

    def test_tracked_reconstruction_profile_has_qualified_budget(self):
        qualified = validate_reconstruction_profile(self.profile_value)
        self.assertEqual(qualified.total_context_tokens, 32768)
        self.assertEqual(qualified.instruction_token_limit, 2048)
        self.assertEqual(qualified.conversation_token_limit, 12288)
        self.assertEqual(qualified.evidence_token_limit, 16384)
        self.assertEqual(qualified.answer_token_reserve, 2048)
        self.assertEqual(qualified.generation_prompt_targets, (8192, 12288, 16384))
        self.assertEqual(qualified.generation_optional_group_limit, 6)
        self.assertEqual(
            (qualified.temperature, qualified.top_p, qualified.top_k),
            (1.0, 0.95, 64),
        )

    def test_reconstruction_profile_rejects_partition_gap(self):
        changed = json.loads(json.dumps(self.profile_value))
        changed["budget"]["evidence_token_limit"] -= 1
        with self.assertRaisesRegex(ReconstructionContractError, "exactly equal"):
            validate_reconstruction_profile(changed)

    def test_reconstruction_profile_rejects_context_above_service(self):
        changed = json.loads(json.dumps(self.profile_value))
        changed["generation"]["qualified_service_maximum_tokens"] = 32767
        with self.assertRaisesRegex(ReconstructionContractError, "service maximum"):
            validate_reconstruction_profile(changed)

    def test_reconstruction_profile_rejects_thinking_enabled(self):
        changed = json.loads(json.dumps(self.profile_value))
        changed["generation"]["enable_thinking"] = True
        with self.assertRaisesRegex(ReconstructionContractError, "not qualified"):
            validate_reconstruction_profile(changed)

    def test_policy_identity_is_deterministic_and_setting_sensitive(self):
        self.assertEqual(policy().digest, policy().digest)
        self.assertNotEqual(policy().digest, policy(evidence_token_limit=39).digest)

    def test_partition_overcommit_is_rejected(self):
        with self.assertRaisesRegex(ReconstructionContractError, "exceed"):
            policy(evidence_token_limit=41)

    def test_invalid_token_counter_result_is_rejected(self):
        with self.assertRaisesRegex(ReconstructionContractError, "token counter"):
            assemble_evidence(
                (candidate("a"),),
                policy=policy(),
                token_counter=lambda _text: 0,
                instruction_tokens=1,
                conversation_tokens=1,
            )


class DeduplicationTests(unittest.TestCase):
    def test_exact_chunk_duplicate_merges_citations(self):
        first = candidate("same", citation_label="citation:first")
        second = replace(
            first,
            citations=(replace(first.citations[0], citation_id=identity("citation:second")),),
        )
        result, actions = deduplicate_candidates((first, second))
        self.assertEqual(len(result), 1)
        self.assertEqual(len(result[0].citations), 2)
        self.assertEqual(actions[0].reason, "exact_chunk_identity")

    def test_exact_projection_duplicate_merges_cross_document_citations(self):
        first = candidate("first", text="same exact projection", document="alpha")
        second = candidate("second", text="same exact projection", document="beta", rank=2)
        result, actions = deduplicate_candidates((first, second))
        self.assertEqual(len(result), 1)
        self.assertEqual(len(result[0].citations), 2)
        self.assertEqual(actions[0].reason, "exact_retrieval_projection")

    def test_distinct_passages_from_one_document_remain(self):
        result, _ = deduplicate_candidates((candidate("a"), candidate("b", rank=2, ordinal=1)))
        self.assertEqual(len(result), 2)


class BudgetAndGroupingTests(unittest.TestCase):
    def test_document_groups_have_stable_labels_and_multiple_excerpts(self):
        package = assemble_evidence(
            (candidate("a"), candidate("b", rank=2, ordinal=1), candidate("c", rank=3, document="beta")),
            policy=policy(),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
        )
        self.assertEqual(package.status, "ok")
        self.assertEqual([item.source_label for item in package.source_groups], ["Source 1", "Source 2"])
        self.assertEqual(len(package.source_groups[0].passage_ids), 2)

    def test_normal_diversity_omits_only_excess_passages(self):
        package = assemble_evidence(
            tuple(candidate(str(index), rank=index + 1, ordinal=index) for index in range(3)),
            policy=policy(),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
        )
        self.assertEqual(len(package.selected), 2)
        self.assertEqual(package.omitted[0].reason, "document_diversity_limit")

    def test_diversity_counts_structural_groups_not_their_authoritative_atoms(self):
        candidates = (
            candidate("a1", rank=1, ordinal=1, group="page-one"),
            candidate("a2", rank=2, ordinal=2, group="page-one"),
            candidate("b1", rank=3, ordinal=3, group="page-two"),
            candidate("b2", rank=4, ordinal=4, group="page-two"),
            candidate("c1", rank=5, ordinal=5, group="page-three"),
        )
        package = assemble_evidence(
            candidates,
            policy=policy(normal_per_document_limit=2),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
        )
        self.assertEqual(
            [item.text for item in package.selected],
            ["Step a1", "Step a2", "Step b1", "Step b2"],
        )
        self.assertEqual([item.reason for item in package.omitted], ["document_diversity_limit"])

    def test_structural_group_is_omitted_whole_when_it_exceeds_budget(self):
        candidates = (
            candidate("a1", text="one two three", rank=1, ordinal=1, group="page-one"),
            candidate("a2", text="four five six", rank=2, ordinal=2, group="page-one"),
            candidate("b1", text="short", rank=3, ordinal=3, group="page-two"),
        )
        package = assemble_evidence(
            candidates,
            policy=policy(evidence_token_limit=5),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
        )
        self.assertEqual([item.text for item in package.selected], ["short"])
        self.assertEqual(
            [item.reason for item in package.omitted],
            ["evidence_budget_limit", "evidence_budget_limit"],
        )

    def test_explicit_document_uses_qualified_higher_limit(self):
        candidates = tuple(candidate(str(index), rank=index + 1, ordinal=index) for index in range(4))
        package = assemble_evidence(
            candidates,
            policy=policy(),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
            explicit_document_version_id=candidates[0].primary_version_id,
        )
        self.assertEqual(len(package.selected), 4)

    def test_atomic_passage_is_omitted_not_clipped(self):
        long = candidate("long", text=" ".join(["word"] * 41))
        package = assemble_evidence(
            (candidate("short"), long),
            policy=policy(),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
        )
        self.assertEqual([item.text for item in package.selected], ["Step short"])
        self.assertEqual(package.omitted[0].reason, "evidence_budget_limit")
        self.assertNotIn(long.retrieval_text, [item.text for item in package.selected])

    def test_conversation_limit_fails_closed_without_silent_discard(self):
        package = assemble_evidence(
            (candidate("a"),),
            policy=policy(),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=21,
        )
        self.assertEqual((package.status, package.reason_code), ("context-limit", "CONVERSATION_CONTEXT_LIMIT"))
        self.assertEqual(package.selected, ())

    def test_relationship_provenance_survives_reconstruction(self):
        package = assemble_evidence(
            (candidate("related", origin="relationship"),),
            policy=policy(),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
        )
        self.assertEqual(package.selected[0].inclusion_reason, "explicit_reference_one_hop")
        self.assertEqual(len(package.selected[0].relationship_provenance), 1)

    def test_direct_and_relationship_duplicates_keep_required_provenance(self):
        direct = candidate("same", group="page-one")
        related = replace(
            direct,
            retrieval_group_id="relationship-page-one",
            origin="relationship",
            inclusion_reason="explicit_reference_one_hop",
            relationship_provenance=(
                identity("edge:same"),
                identity("seed:same"),
                identity("target:same"),
                identity("version:same"),
                identity("citation:same"),
            ),
        )
        deduplicated, _actions = deduplicate_candidates((direct, related))
        self.assertEqual(deduplicated[0].origin, "relationship")
        self.assertEqual(deduplicated[0].inclusion_reason, "explicit_reference_one_hop")
        self.assertEqual(deduplicated[0].retrieval_group_id, "page-one")
        self.assertEqual(
            deduplicated[0].relationship_provenance,
            related.relationship_provenance,
        )
        self.assertEqual(
            deduplicated[0].relationship_provenance[0],
            identity("edge:same"),
        )

    def test_explicit_relationship_unit_is_reserved_before_direct_document_slots(self):
        direct = tuple(
            candidate(
                f"direct-{index}",
                rank=index,
                ordinal=index,
                group=f"direct-page-{index}",
            )
            for index in range(1, 4)
        )
        related = candidate(
            "related",
            rank=4,
            ordinal=4,
            origin="relationship",
            group="located-reference-page",
        )
        package = assemble_evidence(
            (*direct, related),
            policy=policy(normal_per_document_limit=3),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
            require_relationship_coverage=True,
        )
        self.assertEqual(
            [item.text for item in package.selected],
            ["Step related", "Step direct-1", "Step direct-2"],
        )
        self.assertEqual(
            [item.text for item in package.selected if item.relationship_provenance],
            ["Step related"],
        )

    def test_explicit_relationship_seed_is_reserved_before_ordinary_direct_units(self):
        seed = candidate(
            "seed", rank=4, ordinal=4, group="seed-page",
            citation_label="seed-citation",
        )
        ordinary = tuple(
            candidate(
                f"direct-{index}",
                rank=index,
                ordinal=index,
                group=f"direct-page-{index}",
            )
            for index in range(1, 4)
        )
        related = replace(
            candidate(
                "related", rank=5, ordinal=5, document="beta",
                origin="relationship", group="located-reference-page",
            ),
            relationship_provenance=(
                identity("edge:seed-target"),
                seed.primary_document_id,
                identity("document:beta"),
                identity("version:beta"),
                seed.citations[0].citation_id,
            ),
        )
        package = assemble_evidence(
            (*ordinary, seed, related),
            policy=policy(normal_per_document_limit=2),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
            require_relationship_coverage=True,
        )
        self.assertEqual(
            [item.text for item in package.selected],
            ["Step related", "Step seed", "Step direct-1"],
        )

    def test_ordinary_question_prioritizes_direct_units_before_relationship_context(self):
        direct = tuple(
            candidate(
                f"direct-{index}",
                rank=index,
                ordinal=index,
                group=f"direct-page-{index}",
            )
            for index in range(1, 4)
        )
        related = candidate(
            "related",
            rank=4,
            ordinal=4,
            origin="relationship",
            group="located-reference-page",
        )
        package = assemble_evidence(
            (*direct, related),
            policy=policy(normal_per_document_limit=3),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
        )
        self.assertEqual(
            [item.text for item in package.selected],
            ["Step direct-1", "Step direct-2", "Step direct-3"],
        )

    def test_generation_admits_only_three_highest_ranked_relationship_groups(self):
        seeds = tuple(
            candidate(
                f"seed-{index}",
                rank=index,
                ordinal=index,
                document=f"seed-{index}",
                group=f"seed-page-{index}",
                citation_label=f"seed-citation-{index}",
            )
            for index in range(1, 5)
        )
        relationships = tuple(
            replace(
                candidate(
                    f"target-{index}",
                    rank=index,
                    ordinal=index,
                    document=f"target-{index}",
                    origin="relationship",
                    group=f"target-page-{index}",
                ),
                relationship_provenance=(
                    identity(f"edge:{index}"),
                    seeds[index - 1].primary_document_id,
                    identity(f"document:target-{index}"),
                    identity(f"version:target-{index}"),
                    seeds[index - 1].citations[0].citation_id,
                ),
            )
            for index in range(1, 5)
        )
        package = assemble_evidence(
            (*seeds, *relationships),
            policy=policy(
                total_context_tokens=400,
                evidence_token_limit=340,
                normal_per_document_limit=3,
            ),
            token_counter=count_words,
            instruction_tokens=20,
            conversation_tokens=20,
        )
        selected_relationships = {
            item.relationship_provenance[0]
            for item in package.selected
            if item.relationship_provenance
        }
        self.assertEqual(
            selected_relationships,
            {identity("edge:1"), identity("edge:2"), identity("edge:3")},
        )
        self.assertNotIn("Step target-4", [item.text for item in package.selected])
        self.assertEqual(
            [item.reason for item in package.actions].count(
                "relationship_generation_group_limit"
            ),
            1,
        )

    def test_excluded_relationship_route_does_not_remove_same_direct_atom(self):
        relationships = tuple(
            replace(
                candidate(
                    f"target-{index}",
                    rank=index,
                    ordinal=index,
                    document=f"target-{index}",
                    origin="relationship",
                    group=f"target-page-{index}",
                ),
                relationship_provenance=(identity(f"edge:{index}"),),
            )
            for index in range(1, 5)
        )
        direct_fourth = replace(
            relationships[3],
            origin="direct",
            inclusion_reason="direct_retrieval",
            relationship_provenance=(),
        )
        package = assemble_evidence(
            (*relationships, direct_fourth),
            policy=policy(
                total_context_tokens=400,
                evidence_token_limit=340,
                normal_per_document_limit=3,
            ),
            token_counter=count_words,
            instruction_tokens=20,
            conversation_tokens=20,
        )
        fourth = next(item for item in package.selected if item.text == "Step target-4")
        self.assertEqual(fourth.relationship_provenance, ())
        self.assertEqual(fourth.inclusion_reason, "direct_retrieval")

    def test_relationship_limit_counts_identities_not_structural_atoms(self):
        relationships = (
            replace(
                candidate(
                    "target-1a", rank=1, ordinal=1, document="target-1",
                    origin="relationship", group="target-page-1",
                ),
                relationship_provenance=(identity("edge:1"),),
            ),
            replace(
                candidate(
                    "target-1b", rank=2, ordinal=2, document="target-1",
                    origin="relationship", group="target-page-2",
                ),
                relationship_provenance=(identity("edge:1"),),
            ),
            *(
                replace(
                    candidate(
                        f"target-{index}",
                        rank=index + 1,
                        ordinal=index + 1,
                        document=f"target-{index}",
                        origin="relationship",
                        group=f"target-page-{index}",
                    ),
                    relationship_provenance=(identity(f"edge:{index}"),),
                )
                for index in range(2, 5)
            ),
        )
        package = assemble_evidence(
            relationships,
            policy=policy(
                total_context_tokens=400,
                evidence_token_limit=340,
                normal_per_document_limit=3,
            ),
            token_counter=count_words,
            instruction_tokens=20,
            conversation_tokens=20,
        )
        selected_relationships = [
            item.relationship_provenance[0]
            for item in package.selected
            if item.relationship_provenance
        ]
        self.assertEqual(selected_relationships.count(identity("edge:1")), 2)
        self.assertEqual(
            set(selected_relationships),
            {identity("edge:1"), identity("edge:2"), identity("edge:3")},
        )
        self.assertNotIn(identity("edge:4"), selected_relationships)


class CompleteProcedureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        artifact_path = (
            Path(__file__).resolve().parent
            / "fixtures/reconstruction/structural_chunk_candidates.json"
        )
        artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
        document = next(item for item in artifact["documents"] if item["document_ref"] == "SYN-006")
        cls.inventory = tuple(cls._from_artifact(document, item, index + 1) for index, item in enumerate(document["candidates"]))
        cls.version_id = document["document_version_id"]

    @staticmethod
    def _from_artifact(document, raw, rank):
        anchor = raw["citation_anchor"]
        citation = EvidenceCitation(
            citation_id=domain_digest(
                "ishikawa.citation.v1",
                {"chunk_id": raw["chunk_id"], "page_start": anchor["page_start"], "page_end": anchor["page_end"]},
            ),
            document_id=document["document_id"],
            document_version_id=document["document_version_id"],
            document_key="procedure.incident-reporting",
            page_start=anchor["page_start"],
            page_end=anchor["page_end"],
            structural_path=tuple(anchor["structural_path"]),
        )
        return EvidenceCandidate(
            chunk_id=raw["chunk_id"],
            retrieval_text_digest=raw["retrieval_text_digest"],
            retrieval_text=raw["retrieval_text"],
            projection_kind=raw["projection_kind"],
            ordinal=raw["projection_properties"].get("source_ordinal", rank - 1),
            retrieval_rank=rank,
            origin="direct",
            inclusion_reason="direct_retrieval",
            citations=(citation,),
        )

    def test_complete_procedure_requires_complete_inventory(self):
        target = CompleteProcedureTarget(self.version_id, ())
        with self.assertRaisesRegex(ReconstructionContractError, "complete document inventory"):
            reconstruct_complete_procedure(target, self.inventory, inventory_complete=False)

    def test_section_reconstruction_uses_exact_structural_path_and_source_order(self):
        target = CompleteProcedureTarget(self.version_id, ("II. Triage Sequence",))
        result = reconstruct_complete_procedure(target, self.inventory, inventory_complete=True)
        self.assertEqual(len(result), 3)
        self.assertEqual([item.ordinal for item in result], sorted(item.ordinal for item in result))
        self.assertTrue(all(item.citations[0].structural_path == target.structural_path for item in result))

    def test_whole_procedure_reconstruction_includes_all_semantic_candidates(self):
        target = CompleteProcedureTarget(self.version_id, ())
        result = reconstruct_complete_procedure(target, self.inventory, inventory_complete=True)
        self.assertEqual(len(result), len(self.inventory))
        self.assertEqual([item.ordinal for item in result], sorted(item.ordinal for item in result))
        self.assertTrue(all(item.inclusion_reason == "complete_procedure" for item in result))

    def test_complete_procedure_is_all_or_context_limit(self):
        target = CompleteProcedureTarget(self.version_id, ("II. Triage Sequence",))
        reconstructed = reconstruct_complete_procedure(target, self.inventory, inventory_complete=True)
        package = assemble_evidence(
            reconstructed,
            policy=policy(evidence_token_limit=5),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
            complete_procedure=True,
        )
        self.assertEqual((package.status, package.reason_code), ("context-limit", "COMPLETE_PROCEDURE_CONTEXT_LIMIT"))
        self.assertEqual(package.selected, ())
        self.assertEqual(len(package.omitted), 3)

    def test_complete_procedure_fits_as_ordered_atomic_package(self):
        target = CompleteProcedureTarget(self.version_id, ("II. Triage Sequence",))
        reconstructed = reconstruct_complete_procedure(target, self.inventory, inventory_complete=True)
        package = assemble_evidence(
            reconstructed,
            policy=policy(evidence_token_limit=40),
            token_counter=count_words,
            instruction_tokens=5,
            conversation_tokens=5,
            complete_procedure=True,
        )
        self.assertEqual(package.status, "ok")
        self.assertEqual(len(package.selected), 3)
        self.assertEqual([item.source_ordinal for item in package.selected], sorted(item.source_ordinal for item in package.selected))
        self.assertEqual(len(package.source_groups), 1)


if __name__ == "__main__":
    unittest.main()
