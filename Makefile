.PHONY: app run stop clean export-models install-models

app:
	./scripts/build-app.sh release

export-models:
	./scripts/models.sh export

install-models:
	./scripts/models.sh install $(FILE)

install-models-from-repo:
	./scripts/models.sh install-from-repo

run: app
	open build/Dictator.app

stop:
	-pkill -x Dictator

clean:
	rm -rf .build build
