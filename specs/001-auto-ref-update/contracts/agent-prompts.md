# Contract: Agent Prompt Interfaces

**Feature**: `001-auto-ref-update` | **Date**: 2026-03-09

Defines the required inputs and expected output formats for the generator and reviewer agents. These contracts govern what the `invoke-agent.sh` script passes and expects back.

---

## Generator Agent Contract

**Purpose**: Transform fetched source content into updated reference documentation.

### Required Inputs

Passed as a structured prompt containing all of the following:

| Input | Description |
|-------|-------------|
| Existing reference file content | The current content of the reference file (or section if `section` is set) |
| Fetched source content | All files from the sparse checkout, concatenated with filename headers |
| Section scope | If `section` is set: agent MUST update only that named section, leaving all other content verbatim |
| Traceability metadata | `source_repo_id`, `ref`, `commit`, `updated` — to be written as frontmatter |
| Output format instruction | Agent MUST return the complete updated file (or section) content, nothing else |

### Expected Output

The generator agent MUST return:
1. Valid Markdown with traceability frontmatter at the top (for full-file updates)
2. Only the updated section content (for section-scoped updates — frontmatter is added by the script)
3. No explanation text, no preamble, no commentary — only the document content

### Section Splicing (section-scoped updates only)

When `section` is set, the script is responsible for splicing the generator's output back into the full reference file. The script MUST:

1. Locate the section boundary in the existing file by matching the heading `## <section>` (case-sensitive)
2. Identify the end of that section as either the next `##`-level heading or end-of-file
3. Replace only the content between those boundaries with the generator's output
4. Preserve all other sections verbatim
5. Update the traceability frontmatter to reflect the new commit SHA and date for the contributing repo, while preserving existing entries for other repos

**Heading drift**: If the section heading is not found in the existing file, the script MUST fail loudly (`exit 1`) rather than appending or overwriting the full file. This forces an explicit human decision when source repo restructuring causes section names to diverge.

**Output validation** (performed by script before passing to reviewer):
- Non-empty content
- Traceability frontmatter block present and parseable (full-file updates only)
- Content differs from existing file/section (if identical, skip — no PR needed)

---

## Reviewer Agent Contract

**Purpose**: Evaluate the generator agent's output for quality, accuracy, and compliance.

### Required Inputs

Passed as a structured prompt containing:

| Input | Description |
|-------|-------------|
| Generator's output | The complete proposed content (file or section) |
| Source material | The fetched source files used to generate it |
| Review criteria | The criteria below, embedded verbatim in the prompt |
| Traceability block | The frontmatter from the output — reviewer must validate it |

**Review criteria embedded in prompt**:
```
Evaluate the proposed reference document update against these criteria:
1. Accuracy: Does the content correctly reflect the source material?
2. Completeness: Are all public API signatures, parameters, return types, and constraints present?
3. Agent-consumability: Is the content precise and structured for AI consumption (no vague prose, no marketing language)?
4. Traceability: Is the frontmatter block present, correctly formatted, and does the commit SHA match the source?
5. Scope compliance: If a section was specified, does the update touch ONLY that section?

Respond in this exact format:
VERDICT: ACCEPT
FINDINGS: <one paragraph, or "None." if no issues>

OR:

VERDICT: REJECT
FINDINGS: <specific issues found, referenced by section or line>
```

### Expected Output

The reviewer agent MUST return a response matching this exact format:

```
VERDICT: ACCEPT
FINDINGS: <text>
```

or

```
VERDICT: REJECT
FINDINGS: <text>
```

**Parsing rule**: The script extracts `VERDICT:` value (case-insensitive match for `ACCEPT` or `REJECT`) and everything after `FINDINGS:` as the findings text. Any other format causes the step to fail with an error.

**Behaviour based on verdict**:
- `ACCEPT`: proceed to write files to `plugins/` and open/update PR without `needs-review` label
- `REJECT`: proceed to open/update PR WITH `needs-review` label; findings appear in PR body

---

## Script Invocation Interface

`scripts/sync/invoke-agent.sh` is called by the main workflow:

```bash
invoke-agent.sh \
  --role generator|reviewer \
  --agent claude|codex|gemini \
  --prompt-file /path/to/prompt.md \
  --output-file /path/to/output.md
```

**Exit codes**:

| Exit Code | Meaning |
|-----------|---------|
| `0` | Agent responded with parseable output |
| `1` | Agent invocation failed (API error, timeout, empty response) |
| `2` | Reviewer output did not match expected format |
