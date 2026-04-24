# pccx — Sail ISA model make targets.
#
# Sail (>= 0.20.1) is expected on PATH.  If it was installed via opam
# and not re-exported, invoke `eval $(opam env)` once per shell or use
# the absolute path:
#   make SAIL=~/.opam/default/bin/sail check
#
# Targets:
#   check   type-check the full module tree (default)
#   doc     emit model documentation (requires Sail `doc` plugin)
#   clean   remove build artefacts

SAIL         ?= sail
PROJECT      := pccx.sail_project

.PHONY: check doc clean

check:
	$(SAIL) --project $(PROJECT) --all-modules --just-check

doc:
	$(SAIL) --project $(PROJECT) --all-modules --doc -o build/pccx

clean:
	rm -rf build
