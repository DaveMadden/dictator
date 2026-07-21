# Dictator speech models (distribution branch)

This orphan branch carries the Parakeet TDT 0.6B v3 CoreML models
(CC-BY-4.0, by NVIDIA; CoreML conversion by the FluidAudio project) as a
gzipped tarball split into <100MB chunks, so a machine that can reach GitHub
— and nothing else — can install Dictator fully offline.

Don't use this branch directly; from a clone of `main`, run:

```sh
./scripts/models.sh install-from-repo
```

which fetches this branch, reassembles the tarball, verifies its SHA-256,
and installs the models into `~/Library/Application Support/Dictator/models/`.
