# Documentation

The project's story in reading order, plus the references. Every document says what it
is for in its first paragraph. When code and a document disagree, the document is fixed
in the same change.

| Read | Document | What it holds |
|---|---|---|
| 1 | [DESIGN.md](DESIGN.md) | Design and planning, written before the code: requirements, the login flow, the run pipeline, threat model, data model, configuration, scaling, the change map |
| 2 | [IMPLEMENTATION.md](IMPLEMENTATION.md) | What was built and how it behaves in production: topology, a run end to end with measured timings, decisions with trade-offs, security posture and findings, performance, incidents and lessons |
| 3 | [TESTING.md](TESTING.md) | The test-first rule, the layers, the hostile programs, the live probes |
| 4 | [DEPLOYMENT.md](DEPLOYMENT.md) | The deployment shape, what to supply, a deploy step by step, failure modes, daily checks, incident playbooks, secrets, backups, capacity knobs, teardown |
| 5 | [FUTURE-SCOPE.md](FUTURE-SCOPE.md) | What comes next in priority order, the scaling path, known limits |
| ref | [QUESTIONS.md](QUESTIONS.md) | Questions a reviewer might ask, with answers |
| ref | [../CONTRIBUTING.md](../CONTRIBUTING.md) | Development workflow, code map, how to add common things, copy voice, troubleshooting |
| ref | [../CHANGELOG.md](../CHANGELOG.md) | History by theme and date |
| ref | [../examples/](../examples/) | Scripts to paste into the editor for a demo |

## Your first day

1. Read the README and run the app locally (`bin/setup`, `bin/dev`). Sign up, run
   `examples/balloon_ascent.py`, press Stop on a second run, open the admin pages.
2. Read IMPLEMENTATION.md sections 1 to 3: the three processes, how a run flows, why
   the big choices were made.
3. Read CONTRIBUTING.md and TESTING.md, then run the suite by layer. Open one test file
   per layer and the service it exercises.
4. Keep DESIGN.md for the full reasoning; its section 15, the change map, is the fastest
   answer to "how many places do I touch for X?".
5. If you will look after the live system, read DEPLOYMENT.md end to end once.

Nothing here names a host, an account or an address; those live in untracked files
described in DEPLOYMENT.md.
