# Import Manifest

This manifest records the immutable source tips used for the initial monorepo
integration. Source commits remain ancestors of `main`; their trees were moved
without content changes in one relocation commit per repository.

| Source repository | Source tip | Monorepo path | Relocation commit | Merge commit |
| --- | --- | --- | --- | --- |
| `mjy9088/codyssey-init` | `4918bf8408a81cdd17c4ef3815862db0225cbcca` | `environment/codyssey-init/` | `5598183` | `deeca1e` |
| `mjy90884682/E1-1` | `9780e2e68d1d1fcd6f0b51204ea9871b7b19e4ba` | `archive/E1-1/` | `55e918c` | `47b4478` |
| `mjy90884682/E1-2` | `21b92f16e822ca2eaa32ed8b7ba5765f2621d989` | `archive/E1-2/` | `47c0c9d` | `6fb6cc0` |
| `mjy90884682/E1-3` | `68c9bb75b10231386562749b2e3ba3644e55eeca` | `archive/E1-3/` | `765de09` | `c303e74` |

## Verification method

For each import, the sorted set of Git object modes, types, and blob IDs from
the source tip was compared with the corresponding relocated subtree. Each
source tip was also verified as an ancestor of the integrated `main` branch.
This checks both byte-for-byte tree preservation and history reachability.

The import branches and auxiliary remotes are local integration aids. The
durable provenance is the commit graph reachable from `main` plus this manifest.
