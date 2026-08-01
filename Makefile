.PHONY: test build package verify verify-startup-ui

test:
	swift test --parallel

build:
	swift build -c release

package:
	bash scripts/package-app.sh

verify:
	bash scripts/verify-local.sh

verify-startup-ui: package
	bash scripts/verify-startup-ui.sh
