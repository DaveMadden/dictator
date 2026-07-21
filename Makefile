.PHONY: app app-full audit run stop clean install install-full export-models install-models install-models-from-repo

# Default build: no inference engine, no downloader, no network-capable code.
app:
	./scripts/build-app.sh release

# Opt-in extras for personal machines: embedded llama.cpp polish and the
# Hugging Face model downloader.
app-full:
	DICTATOR_LLM=1 DICTATOR_DOWNLOAD=1 ./scripts/build-app.sh release

# Prints every network-capable symbol reachable in the built binary.
audit:
	./scripts/audit-network.sh

export-models:
	./scripts/models.sh export

install-models:
	./scripts/models.sh install $(FILE)

install-models-from-repo:
	./scripts/models.sh install-from-repo

run: app
	open build/Dictator.app

# Copies the app to /Applications so Spotlight finds it and it survives
# restarts. After installing: grant Accessibility for the new copy, then
# enable Settings → Launch at login.
install: app
	-pkill -x Dictator
	rm -rf /Applications/Dictator.app
	cp -R build/Dictator.app /Applications/
	open /Applications/Dictator.app

install-full: app-full
	-pkill -x Dictator
	rm -rf /Applications/Dictator.app
	cp -R build/Dictator.app /Applications/
	open /Applications/Dictator.app

stop:
	-pkill -x Dictator

clean:
	rm -rf .build build
