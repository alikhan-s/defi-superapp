.PHONY: coverage coverage-html

coverage:
	forge coverage --no-match-coverage "(script|test|lib)"

coverage-html:
	forge coverage --no-match-coverage "(script|test|lib)" --report lcov
	genhtml lcov.info -o coverage-html --branch-coverage
