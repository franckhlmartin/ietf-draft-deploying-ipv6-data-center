SOURCE = draft-martin-deploying-ipv6-data-center.md
VERSION := $(shell grep -E '^value = "draft-martin-deploying-ipv6-data-center-' $(SOURCE) | sed -n 's/.*-\([0-9][0-9]\)".*/\1/p')
DRAFT = draft-martin-deploying-ipv6-data-center-$(VERSION)

GOPATH := $(shell go env GOPATH 2>/dev/null)
VENV := $(CURDIR)/.venv
PYTHON := $(shell command -v python3.12 2>/dev/null || command -v python3 2>/dev/null)

MMARK := $(GOPATH)/bin/mmark
XML2RFC := $(VENV)/bin/xml2rfc

all: deps $(DRAFT).xml $(DRAFT).txt $(DRAFT).html

deps: $(MMARK) $(XML2RFC)

$(MMARK):
	@test -n "$(GOPATH)" || { echo "Go is not installed. See https://go.dev/dl/"; exit 1; }
	go install github.com/mmarkdown/mmark/v2@latest

$(XML2RFC):
	@test -n "$(PYTHON)" || { echo "Python 3 is not installed."; exit 1; }
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip xml2rfc

$(DRAFT).xml: $(SOURCE) $(MMARK) scripts/fix-mmark-xml.py
	$(MMARK) $< > $@.tmp
	$(PYTHON) scripts/fix-mmark-xml.py $@.tmp
	mv $@.tmp $@

$(DRAFT).txt: $(DRAFT).xml $(XML2RFC)
	$(XML2RFC) $< --text -o $@

$(DRAFT).html: $(DRAFT).xml $(XML2RFC)
	$(XML2RFC) $< --html -o $@

lint: $(DRAFT).xml
	@command -v idnits >/dev/null || { \
		echo "idnits not found. Install with: npm install -g @ietf-tools/idnits"; \
		exit 1; \
	}
	idnits $<

clean:
	rm -f draft-martin-deploying-ipv6-data-center-*.xml draft-martin-deploying-ipv6-data-center-*.txt draft-martin-deploying-ipv6-data-center-*.html

clean-all: clean
	rm -rf $(VENV)

.PHONY: all deps lint clean clean-all
