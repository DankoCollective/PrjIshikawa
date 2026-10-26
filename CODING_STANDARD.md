# CODING_STANDARD.md

## File Contract
- Role: canonical repo-wide authoring standard for code files, operator-facing scripts, and shared script modules
- Scope: how code and scripts should be structured, named, commented, and explained in any repository using this control surface
- Use: open this file when creating, reviewing, or tightening code or scripts, or when reconciling repository style across workstreams
- Not this file: live current state, task-local workflow decisions, or reusable run procedure
- Conflict rule: when this file conflicts with a language, framework, or integration constraint, keep the implementation correct and document the narrow exception explicitly

## Current Repo Posture
- a repository may include application code, operator-facing scripts, reviewed orchestration helpers, and workstream-specific script lanes
- this file is binding for ordinary code, operator-facing scripts, shared script modules, and script-lane README updates
- lab scripts that stage artifacts, copy remote payloads, mutate remote hosts, or create reviewed evidence must also follow `LAB_RUN_PATH_STANDARD.md`

## Purpose
- Make code and scripts human interpretable at file-open, not only after reverse-engineering the implementation
- Keep the file-open view as a live definition of the file's authoritative implementation
- Keep main execution flow and class responsibility readable from top to bottom
- Prevent clever or compressed file shapes that save typing but raise operator or maintainer effort

## File Categories
- `Application code file`:
  - a source file that defines service entrypoints, classes, helpers, models, or other implementation logic
  - examples: host entrypoints, service classes, helper classes, record-mapping classes
- `Operator-facing entrypoint script`:
  - a script the operator may run directly from the shell
  - examples: numbered operator scripts such as `10_...`, `20_...`, `30_...`, and reviewed orchestration helpers
- `Shared script module`:
  - a helper file imported or sourced by operator-facing scripts
  - examples: `_build_common.py`, `_deployment_common.py`
- `Orchestration shell script`:
  - a reviewed multi-step shell entrypoint that coordinates several lower-level steps

## File-Open Readability Standard

### Core Rule
- A human opening the file should be able to identify its role quickly
- The opening section of the file should make the primary behavior or responsibility legible without deep scrolling
- If implementation changes materially, update any header, summary, or nearby explanation in the same pass

### Application Code File Standard
- The file should make the primary type or responsibility obvious near the top
- Prefer one clear primary responsibility per file
- If the file contains a non-obvious class, helper, or transformation, add a concise file-open or class-level explanation
- Do not use a file-open comment block as a changelog or historical note dump
- If the class performs important side effects such as database writes, network calls, or runtime-state mutation, that should be discoverable through names, nearby comments, or surrounding docs

### Operator-Facing Script Header Shape
- `Purpose`:
  - what the script does in repo terms
- `Mental model`:
  - the execution flow in plain English
  - how the script should be mentally understood by a human reader
- `Inputs or prerequisites`:
  - required parameters, required environment, secrets, or host assumptions when they are not obvious
- `Outputs or artifact lane`:
  - what the script writes and where
- `Usage`:
  - a short, real command example when it materially helps the operator

### Header Interpretation Rules
- File-open guidance is authoritative for the intended live behavior of the file
- It should be descriptive, not promotional
- Do not use it as a changelog
- Do not use it to explain how the file evolved over time
- Troubleshooting notes belong in evidence, docs, or the relevant README, not in the file-open mental model

### Shared Helper Module Header Shape
- A shared helper module may use a shorter header
- It should still state:
  - the module role
  - what operator-facing scripts depend on it
  - the mental model of what it centralizes

## Structure Standard

### Main Flow
- Prefer main flow first and lower-level helpers later in the file where syntactically possible
- A human reader should be able to open the file and understand the execution path quickly
- For entrypoint code:
  - host wiring, orchestration, argument parsing, validation, and main execution should stay easy to identify
- For entrypoint scripts:
  - argument parsing, validation, and main orchestration should be near the top-level readable path
- For classes:
  - constructor and primary public behavior should not be buried behind unrelated helper noise

### Classes And Types
- File names should match the primary type where the language and repo conventions expect that relationship
- Keep a class focused on one main responsibility unless a framework pattern clearly requires otherwise
- Do not mix unrelated responsibilities into one class just because the code is nearby
- When a class has both orchestration logic and low-level transformations, keep the orchestration readable and push helper detail downward when possible

### Functions And Methods
- Put helper functions or lower-level methods toward the bottom of the file where syntactically possible
- Do not scatter key helper logic arbitrarily through the file
- Keep the execution path easy to follow without jumping repeatedly between distant helper fragments
- If a language requires a different order, keep the file structured so the main flow is still easy to identify

## Comments And Explanations Standard
- Comments should be present when they reduce interpretation cost
- Use comments to explain:
  - why a step exists
  - why a non-obvious branch is correct
  - why a format, guardrail, workaround, or preserved legacy identifier is necessary
  - why an external contract is intentionally not being renamed yet
- Do not use comments to restate obvious syntax
- Do not fill files with decorative or status-noise comments
- Prefer a small number of high-value comments over line-by-line paraphrasing

## Naming Standard

### Target Implementation Object Names
- Target-host implementation object names must be service/domain meaningful outside this repo
- Do not embed repository workstream names, project names, script numbers, or agent-local labels in systemd drop-ins, service names, config file names, runtime directories, authority paths, policy names, database object names, certificate labels, transfer bundles, operator-facing artifacts, or other live target objects unless the object is explicitly historical repository/evidence material
- For new executable scripts and master replay recipes, prefer portable action/product names instead of workstream-title basenames. Record workstream/script identity in the containing directory, registry entry, report header, or decision/evidence text rather than in names that may be copied into deployed use.
- Existing historical names may be preserved when renaming would break accepted evidence, registry links, or replay history. Do not copy those historical names into new target-side artifacts.
- Report names and evidence files may include workstream/script identifiers because they are control-surface artifacts, not target implementation names
- Prefer names such as:
  - `runtime-paths.conf`
  - `openbao.service`
  - `wso2-is.service`
  - `identity-server-runtime`
- Avoid target object names such as:
  - `project-step-readwrite-paths.conf`
  - `script126-runtime.conf`
  - `project-runtime-paths`
  - bare numeric prefixes such as `10-runtime-paths.conf` unless an external platform requires numeric ordering and the reason is documented

### Types, Files, And Members
- Names should reflect actual implementation role, not vague intent
- Type names should describe the thing being modeled or the work being done
- Method names should describe the behavior they perform
- Variable and parameter names should describe the value they hold
- Avoid generic names such as:
  - `data`
  - `helper`
  - `manager`
  - `process`
  - `thing`
  - `tmp2`

### Variable And Function Names
- Do not use simplified names that force the reader to infer meaning from surrounding code
- Avoid single-character variable, parameter, or function names in repo code unless the language or local mathematical meaning makes them unavoidable
- Name variables relative to what they actually represent in the implementation
- Prefer names such as:
  - `question_text`
  - `retrieval_metadata`
  - `validation_set_path`
  - `prompt_record_path`
  - `notification_payload`
  - `employee_record_batch`
- Avoid names such as:
  - `q`
  - `x`
  - `tmp2`
  - `d`
  - `r`

### Anti-Compression Rule
- Do not compress meaningful logic into short names just because the scope is local
- Loop-local names should still be readable
- If a variable survives long enough to matter, it deserves a meaningful name

## Human Interpretability Standard
- Code and scripts should be understandable by a human opening the file for the first time
- The operator or maintainer should not need to reconstruct the mental model from raw code alone
- Favor explicit flow over clever compactness
- Prefer a small number of clear steps over dense one-liners
- Keep hidden side effects low and visible side effects explicit

## Failure And Side-Effect Standard
- A code or script file should make its major side effects discoverable without reading the entire file
- If the implementation writes artifacts, touches the database, calls network services, or mutates runtime state, that should be visible through the header, class role, command help, method naming, or comments
- Failure should be explicit:
  - return a non-zero exit code for real script execution failure unless a reviewed workstream contract intentionally captures failure in an artifact instead
  - surface plain enough errors that the operator or maintainer can tell what failed without deep code archaeology
- When a file deliberately captures failure into an artifact instead of raising it directly, that behavior should be explained in the relevant README or local docs

## Offline Replay And Safe Rerun Standard
- Offline replayability is a first-class requirement for controlled lab and product rehearsal scripts, not a cleanup task after implementation
- Scripts that stage, carry, install, configure, or mutate state must consider three normal paths: first run, rerun after a blocked or partial run, and offline or bastion replay from captured artifacts
- For approved authority objects such as OpenBao records, service accounts, policies, mounts, database roles, certificate roles, or runtime roots, check whether the object already exists before creating it
- If an approved object exists and is within the frozen posture, reuse it instead of regenerating secret, key, certificate, password, token, or identity material solely to make the script easy to rerun
- If an approved object is missing, create it with an explicit create-only guard, CAS guard, or equivalent existence check where the target API supports one
- For non-secret context, metadata, notes, labels, and evidence pointers, use version-aware updates where supported so reruns can refresh context without replacing protected values
- Do not overwrite, rotate, delete, revoke, or replace live credentials, certificates, artifacts, policies, mounts, service accounts, databases, or trust material unless a frozen decision or explicit operator action approves that mutation
- Material public downloads must use identity-bound persistent staging when technically possible. Reuse or resume checksum-valid bytes after a blocked run, and do not place deletion of reusable model, wheel, package, archive, container, or equivalent payload data in a generic cleanup trap.
- Order capture work so metadata, policy, license, platform, source-host, dependency, and advisory gates run before bulk payload transfer whenever those gates do not require the payload bytes.
- A capture checkpoint may be reused only after its exact artifact identity and checksum manifest pass again. Missing or mismatched identity must block without merging or deleting the staged data.
- Remove persistent public-artifact staging only after checksum-verified promotion or explicit operator rejection. Secret-bearing or private-plaintext temporary work remains subject to prompt bounded cleanup and must not be preserved under this rule.
- Failed candidate work directories that may contain plaintext, private key material, CSR staging, raw config, or temporary secret material must be cleaned by the owning script when safe, or the script must block with explicit cleanup instructions before continuing
- Evidence should record replay-relevant non-secret facts such as object names, versions, hashes, serials, fingerprints, owners, modes, advisory disposition, and accepted report paths, without recording secret values, private keys, tokens, passphrases, raw protected responses, raw PEM private material, or full environment dumps
- Browser/OIDC/SAML redirect diagnostics must not print full effective URLs, authorization URLs, callback URLs with query strings, `code_challenge`, `sessionDataKey`, authorization codes, state values, cookies, or token-like query material. Print path-only redirect metadata, marker booleans, counts, labels, and non-secret endpoint names instead.
- Browser-backed WSO2 UI proof must distinguish static shell reachability from real login flow. A `curl` HTTP `200` for `/console`, `/admin`, `/publisher`, or `/devportal` proves only that the web shell is reachable; it does not prove that the browser JavaScript/OAuth/OIDC callback flow works. Before accepting a WSO2 UI-login gate, verify the relevant browser-auth callback registry or run an approved browser/manual-login proof, and record the limitation if only shell readiness was tested.
- When WSO2 APIM or IS ports, hostnames, service-provider callback URLs, Console/My Account origins, Developer Portal URLs, or browser-facing access paths change after first startup, assume some URL/callback state may be persisted in the product database or service-provider records. Use WSO2-documented management/config surfaces or a read-only persisted-state diagnostic before mutation; do not rely on later `deployment.toml` edits alone to regenerate already-persisted callback posture.

## Runtime Secret Consumer Standard
- Runtime secret consumption is a separate integration decision from storing a secret in the approved authority
- Runtime consumers must be explicitly approved later per service, with service auth, fail-closed behavior, retry behavior, caching rules, lease/rotation handling, and evidence boundaries
- Do not wire an app, API, worker, migration, scheduler, or shell helper to fetch live secrets from OpenBao, a password manager, KMS, Secret Server, or equivalent authority unless that service-specific consumer posture is frozen in the relevant decision record first
- If a service needs a database password, API token, dynamic credential, signing secret, or connection secret at startup, runtime, reconnect, migration, or job execution time, the code or script must make that dependency visible in its file-open header, configuration docs, and evidence boundary
- Secret-fetching code must not print secret values, token values, private keys, passphrases, raw provider responses, raw audit records, or full environment dumps
- If a cache, local injected file, environment variable, sidecar, agent, or fallback credential is approved, document its owner, refresh behavior, failure behavior, rotation trigger, and cleanup/revocation expectations
- This standard is intended to support later CoE discussion: approval of the authority service does not automatically approve every runtime consumer

## Product First-Proof Before Hardening Standard
- For off-the-shelf products such as WSO2, OpenBao, databases, artifact repositories, remote-access services, and similar platform software, prove the vendor-supported minimal runtime first before applying lab hardening or custom runtime posture
- The first proof should use the product's documented install/start path with the smallest safe set of required changes: required runtime dependencies, required datasource settings, required license/advisory/artifact capture, required local bind/port choice, and required secret-handling boundary
- Do not force an approved supporting service such as OpenBao, PostgreSQL, an artifact repository, an IdP, a CA, a reverse proxy, or an observability stack into another off-the-shelf product's bootstrap path before that product has a vendor-supported first runtime proof. Store source-of-truth material in the approved authority when that is the frozen posture, but integrate it into the product runtime only through a later explicit integration or runtime-consumer decision.
- Do not externalize product directories, change product-managed writable paths, add aggressive systemd sandboxing, alter startup-secret mechanisms, redesign product keystore/Secure Vault internals, rename target-side implementation objects, or replace the product's expected bootstrap flow before the first successful service start unless the product cannot safely start without that exception
- If a pre-first-proof custom posture is unavoidable, freeze an explicit exception decision with the exact reason, expected blast radius, rollback path, timebox, and evidence needed to abandon that path
- After first proof passes, layer hardening in separate reviewed steps with one change family per script where practical: filesystem externalization, service-account restrictions, systemd sandboxing, Secure Vault changes, mTLS, LAN exposure, OIDC integration, backup/snapshot posture, and runtime secret consumption
- After any certificate, keystore, truststore, TLS, or mTLS mutation, the next runtime-proof script must include a role-specific pre-start certificate/trust gate before starting the product. At minimum, validate the product-documented config role names, referenced file existence, store openability, expected alias, expected certificate fingerprint or serial, required trust anchors, and evidence from the accepted materialization/activation scripts. Block before service start on mismatch instead of discovering the problem through a long runtime probe.
- Offline replay/master scripts should preserve this order: vendor-supported first proof, accepted baseline, then deliberate hardening. Do not bake a long repair chain into replay as if it were the intended install recipe
- If a hardening path creates repeated repair/probe cycles before first proof, stop and reassess whether to revert to product-default first proof instead of continuing custom repairs

## Deployable Package Final-State Standard
- A fresh-deployment package must create the intended final target directly from a documented clean or supported baseline
- This rule applies to every packaged or installed artifact and object type, including source files, configuration, database schemas, binaries, libraries, container or virtual-machine images, service definitions, policy objects, certificates, templates, generated assets, and other deployment material
- Include only the canonical final files needed to install, configure, run, verify, and remove the delivered target, together with the package manifest, checksums, and necessary operator documentation
- Do not include development repair chains, superseded configuration, trial or probe files, historical migrations, one-time mutation helpers, repository evidence, or repository-specific phase and script jargon in the normal fresh-install path
- If development required a base artifact plus patches, repairs, migrations, conversions, or other mutations, materialize and validate the final result before packaging. Package the final artifact and its final identity, not the ancestor plus the mutation chain. For example, ship the already-patched image rather than the base image and its repair script
- Preserve ancestry, build recipes, patches, and mutation history as source or evidence outside the fresh-deployment payload when they are needed for audit or reproducibility. They do not become installation steps merely because they explain how the final artifact was produced
- For a new database, provide one canonical final schema file that creates the current tables, indexes, views, functions, constraints, and privileges directly. An empty database must not have to replay a sequence such as `0001` through `000N` to reach the accepted target
- Keep deltas, patches, and migrations needed to upgrade any already-installed supported artifact or object in a separately identified upgrade path or upgrade package. Do not place them in the fresh-deployment base package unless the installer has an explicit operator-selected upgrade mode
- Consolidation means the smallest clear set of authoritative final files, with one file per coherent responsibility where practical. Do not combine unrelated responsibilities merely to minimize the file count. If a platform constraint requires more than one file for one responsibility, document the constraint and the role of each file
- Every packaged file must have an installation or runtime purpose and must be accounted for by the package manifest and checksum inventory. Unclassified or unused files must block package acceptance
- Qualify the package from a clean supported baseline and prove that it reaches the accepted final target without post-install repair or mutation steps

## OpenBao Record Context Standard
- When a script creates or mutates a real OpenBao KV v2 secret record, it must attach non-secret OpenBao-native context metadata unless the relevant decision list explicitly freezes a narrower exception
- Use KV `custom_metadata` for operator-readable context such as purpose, consumer, owner, policy posture, rotation expectation, recovery note, evidence pointer, and a context schema version
- Treat KV `custom_metadata` as non-secret but not private: it may be visible to a caller that can read the secret, so never place secret values, token fragments, passwords, passphrases, private identifiers, raw provider responses, raw audit snippets, raw private-key material, raw certificate PEM, or raw config bodies in metadata
- When a script issues or imports OpenBao PKI certificate material that needs operator context, create or update a companion KV context record such as `kv/<environment>/pki/certificates/<certificate-label>` with non-secret certificate purpose, consumer, host, SAN posture, issuer, role, serial/fingerprint, target install path, rotation/retirement note, and evidence pointer
- Repo-side redacted maps remain replay/control-surface records; OpenBao-side context metadata exists so operators can understand secrets and certificates from the OpenBao UI/API without relying on memory or a cross-register lookup
- Evidence may record metadata keys, paths, aliases, fingerprints, hashes, owners, policies, and accepted report pointers, but must not capture secret values, raw protected alias values, raw provider responses, tokens, private keys, or full environment dumps

## SSH Destination Portability Standard
- New operator-facing scripts that initiate SSH or SCP to a lab target must expose the SSH destination as an explicit override instead of embedding only one reachable IP address in the implementation
- A script may retain a documented local/LAN address as its default, but the override must accept at least a validated IPv4 address so the same script can use an approved LAN address or Tailscale address without source modification
- Prefer a transport-neutral new interface such as `<TARGET>_SSH_ADDRESS` or `--ssh-address`; do not name a new general destination override `<TARGET>_LAN_IP`. Preserve an existing published variable when compatibility requires it, document that it is the transport address, and define clear precedence before introducing a replacement alias
- Resolve the selected destination once and use the same exact value for the SSH control connection and every related SSH/SCP operation in that run
- Keep transport routing separate from target identity. Configure and validate the expected remote hostname independently, then verify the remote hostname and any required target markers before mutation
- Treat an address override as a route selection only. It must not silently change the remote user, dedicated SSH identity, authentication model, privilege boundary, or target acceptance criteria
- Keep strict host-key checking enabled for every route. Do not use `StrictHostKeyChecking=no` to make a new LAN, Tailscale IP, or DNS name work. A first-use trust bootstrap must be an explicit operator step after the address-to-target mapping is independently confirmed; normal script execution must use strict checking
- Do not silently fall back from a selected LAN route to Tailscale, or from Tailscale to LAN. Use exactly the selected destination and block clearly if that route fails unless an explicit, reviewed failover design has been approved
- Print and record the selected non-secret SSH address, remote user, and expected hostname before remote work so the operator can explain which route and identity contract the script used
- Document both the default command and the address-override command in `--help`, the file-open usage section, or the owning script-lane README when the script is expected to operate through both LAN and Tailscale
- Tailscale SSH authentication is a separate security mode from ordinary OpenSSH routed over a Tailscale address. If supporting it changes authentication or host-key handling, expose and document that mode explicitly rather than inferring it from a `100.x.y.z` destination
- Apply this standard to new scripts and bring an existing remote script into compliance when its SSH interface is materially revised; a repo-wide retrofit requires its own reviewed scope

## Danko Lab Service-Forwarding Standard
- Read `danko_lab.md` and `local/Port_Forwarding.md` before proposing, documenting, or implementing a Danko Lab SSH service forward
- Treat `local/Port_Forwarding.md` as the canonical operator map for direct forwarding of the accepted `00Danko` service set to DankoSurface or EmceeDanko
- Use one complete tunnel carrying Gemma `8000 -> 18000`, Nomic `8001 -> 18001`, Qwen `8002 -> 18002`, and Dalton `18080 -> 18080`; do not create application-specific aliases or forward only the first service needed
- Bind every consumer endpoint to `127.0.0.1` and connect from the consumer directly to `00Danko`; do not transit through another consumer unless an explicit architecture decision approves the chain
- Use the function-specific identity held on the tunnel origin, `IdentitiesOnly=yes`, `StrictHostKeyChecking=yes`, `ExitOnForwardFailure=yes`, bounded keepalives, and `-N -T`
- Preflight all four consumer ports before launch and report every collision in one pass; do not silently select replacement ports
- Keep route and identity independent: changing between an accepted LAN address and an operator-proved Tailscale address changes only the SSH destination address, never the user, key, host acceptance, or service map
- State explicitly that a tunnel does not start the source services and that listener presence alone does not prove readiness, authentication, model identity, or functional behavior
- Repair or extend the canonical forwarding script/document when the established path is insufficient; do not hand the operator a novel one-off command that drifts from the shared convention
- When the canonical map changes, reconcile `local/Port_Forwarding.md`, `danko_lab.md`, affected forwarding scripts, and every first-class repository copy in the same reviewed change

## CLI And Operator Surface
- Keep scripts CLI-driven rather than interactive by default unless a reviewed exception says otherwise
- For any operator-facing command with multiple substantive stages or an
  expected runtime over 15 seconds, use a live bounded milestone stream: print
  stage start plus pass/block transitions, flush promptly, and emit a
  secret-safe heartbeat at least every 30 seconds during an otherwise quiet
  stage
- A parent wrapper must stream or safely project nested milestone lines while
  retaining verbose detail in its report; never make a long nested command
  appear idle by redirecting all child output until exit
- End with an explicit pass/review/blocked marker, report path, cleanup result,
  and next gate; preserve nonzero nested and signal status so interruption can
  never be reported as success
- Executable wrapper tests must cover visible milestone order, nested failure
  propagation, and signal/interruption behavior for the control flow being
  changed
- Do not print secret values, private keys, tokens, provisioner passwords, raw PEM bodies, raw request/response bodies, or full environment dumps
- On Windows-backed WSL repo mounts such as `/mnt/g`, do not rely on `chmod` as an authoring or validation step for repo files. Write operator commands as `bash ./path/to/script.sh`, reserve `chmod` for `/tmp` payloads or remote Linux paths, and use git executable-bit metadata intentionally when a tracked mode change is required.
- Do not write tokens, passphrases, or durable secrets into shell startup files
- For multi-stage SSH/SCP scripts, front-load authentication before long waits, or reuse an explicit SSH control connection across later SSH/SCP calls
- When an SSH/SCP script copies a remote payload or runs remote work, record copy and remote execution result codes in the local report and write a local blocked summary before exiting nonzero
- When an operator-facing script performs more than one SSH/SCP action against the same host, use `SSH_CONNECTION_REUSE_STANDARD.md` unless there is a documented reason not to; this avoids repeated key passphrase prompts while preserving function-specific SSH identity discipline
- When a long multi-step operator-facing script runs several distinct lanes, prefer a tagged after-action summary that reports per-lane execution time and total runtime
- When those timings matter to later review, write the same after-action timing data into a machine-readable artifact under the script's normal artifact lane rather than leaving it only in terminal scrollback
- When supervised stepping is useful, prefer explicit optional pause mode such as `--pause-at-milestones`
- Keep the default path non-interactive unless a reviewed exception requires otherwise
- Reconcile the script, the script-lane README, and any relevant control-surface pointer when operator-facing behavior changes

## Stream Tagging Standard
- Operator-facing script streams should use stable bracketed tags so the operator can identify what the script is doing without reading surrounding prose
- Prefer specific work-stage tags over broad workstream labels
- Prefer tags such as:
  - `[READINESS]`
  - `[PROFILE]`
  - `[EXTRACT]`
  - `[CHUNK]`
  - `[INGEST]`
  - `[SUMMARY]`
- Avoid tags such as:
  - `[WORKSTREAM]`
  - `[SCRIPT]`
  - `[INFO]`
  - any other label that says where the script belongs but not what the current stream line means
- If a helper function emits tagged output, it should prefix every printed line, not only the first line of a multiline message
- Tag names should stay stable across reruns unless the implementation meaning actually changes
- When a script has both operator-facing output and machine-consumed output modes, do not force human stream tags into the machine-consumed mode
- If a script must emit raw machine-readable lines for another script to consume, keep that mode explicit and separate from the tagged operator stream

## Gap Checks And Common Misreadings
- `Mental model` does not mean a vague slogan; it means a live explanation of the actual execution flow
- `Header` does not mean a historical note block; it means current implementation definition
- `Comments should be provided` does not justify filler comments; comments must lower interpretation cost
- `Functions at the bottom where syntactically possible` does not justify hiding the main execution path; the main flow must still stay readable
- `Human interpretable` does not allow clever compression so long as the author can still follow it; the standard is reader-first, not author-first
- `Descriptive names` does not stop at top-level variables; it applies throughout the file where names carry meaning
- `Code standard` does not mean every file needs a large header block; ordinary code files need clarity first, not ritual

## Help And Usage Surface
- Operator-facing scripts should have a readable `--help` surface or language-equivalent usage output
- Parameter names should match the implementation language and the script header terminology closely enough that the operator does not have to translate between them
- Usage examples in headers or script-lane READMEs should be real command shapes, not placeholders that obscure the actual interface

## Function-Level And Class-Level Readability
- Non-obvious helper functions should be named and commented so their role is understandable without tracing every caller first
- Non-obvious classes should make their responsibility clear through naming and nearby explanation
- When a helper performs a high-risk transformation, ranking step, database mutation, or API dispatch step, add a brief comment explaining the intent of that step
- Prefer small focused helpers over one giant helper that hides several unrelated behaviors behind a generic name

## Minimal Templates

### Operator-Facing Script Header

```text
Purpose:
  What this script does now.

Mental model:
  Step 1 ...
  Step 2 ...
  Step 3 ...

Inputs or prerequisites:
  - required parameter or environment assumption

Outputs:
  - artifact or side effect

Usage:
  ./path/to/script --example value
```

### Non-Obvious Code File Summary

```text
Role:
  What class or helper this file defines.

Mental model:
  What the primary type does.
  What side effects or external contracts matter.
```

## Relationship To Other Control Files
- `AGENT_OPERATION.md` keeps the cross-file rule that code and scripts should be readable at file-open
- `PROJECT_RUNBOOK.md` keeps reusable operator run rules and validation workflow
- `scripts/README.md` files keep local command shape and script-lane context when scripts exist
- this file is the canonical place for repo-wide code and script authoring expectations
