# Contributing

## Conventional Commits

All commits **must** follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type       | When to use                                                          |
|------------|----------------------------------------------------------------------|
| `feat`     | A new feature or contract                                            |
| `fix`      | A bug fix                                                            |
| `test`     | Adding or updating tests (no production code changes)                |
| `docs`     | Documentation only changes                                           |
| `refactor` | Code change that neither fixes a bug nor adds a feature              |
| `chore`    | Build process, tooling, or dependency updates                        |
| `ci`       | Changes to CI/CD configuration files and scripts                     |

### Examples

```
feat(lending): add variable interest rate model
fix(amm): correct slippage calculation in swap
test(vault): add fuzz tests for deposit/withdraw
docs(oracle): document price feed integration
refactor(tokens): extract shared ERC20 base
chore(deps): upgrade openzeppelin to v5.3.0
ci: add coverage threshold check
```

### Scopes (optional but recommended)

Use the module name as scope: `tokens`, `oracle`, `amm`, `lending`, `vault`, `treasury`, `governance`.

## Workflow

1. Fork the repo and create a feature branch off `main`.
2. Write tests before or alongside implementation.
3. Ensure `forge build`, `forge fmt --check`, and `forge test` all pass locally.
4. Open a PR with a clear description. The CI pipeline must be green before merging.
5. Squash-merge to keep a clean linear history.

## Code Style

- Format with `forge fmt` before committing.
- Lint with `solhint 'src/**/*.sol'`.
- Follow the NatSpec convention for all public/external functions.
- Keep contracts focused: one contract per file, one concern per contract.
