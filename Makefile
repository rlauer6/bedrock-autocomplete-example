#-*- mode: makefile; -*-

SHELL := /bin/bash

SITE_DIR=/var/www

HTML_DIR=html/birds
# birds/index.roc
HTML = \
    index.roc

# css/birds.css
CSS_DIR=$(HTML_DIR)/css
CSS = \
    birds.css

AUTOCOMPLETE_DIR=bedrock/autocomplete
# bedrock/autocomplete/birds.json
AUTOCOMPLETE = \
    birds.json

JAVASCRIPT_DIR=$(HTML_DIR)/javascript
# javascript/autocomplete.js
JAVASCRIPT = \
    autocomplete.js

IMAGES_DIR=$(HTML_DIR)/img
# img/birds/*.png

autocomplete-example.tar.gz: $(MANIFEST) $(HTML) $(CSS) $(JSON) $(JAVASCRIPT)
	install_dir=$$(mktemp -d); \
	mkdir -p $$install_dir/$(SITE_DIR)/{$(HTML_DIR),$(CSS_DIR),$(AUTOCOMPLETE_DIR),$(JAVASCRIPT_DIR),$(IMAGES_DIR)}; \
	for f in $(AUTOCOMPLETE); do \
	  cp $$f $$install_dir$(SITE_DIR)/$(AUTOCOMPLETE_DIR)/$$(basename $$f); \
	done; \
	for f in $$(find images -maxdepth 1 -name '*.png'); do \
	  cp $$f $$install_dir$(SITE_DIR)/$(IMAGES_DIR)/$$(basename $$f); \
	done; \
	for f in $(CSS); do \
	  cp $$f $$install_dir$(SITE_DIR)/$(CSS_DIR)/$$f; \
	done; \
	for f in $(HTML); do \
	  cp $$f $$install_dir$(SITE_DIR)/$(HTML_DIR)/$$(basename $$f); \
	done; \
	for f in $(JAVASCRIPT); do \
	  cp $$f $$install_dir$(SITE_DIR)/$(JAVASCRIPT_DIR)/$$f; \
	done; \
	pushd $$install_dir; \
	tar cvzf $(CURDIR)/$@ *; \
	popd; \
	rm -rf $$install_dir

MANIFEST = \
    birds.txt

birds.json: $(MANIFEST)
	if [[ "$$MAX_BIRDS" ]]; then \
	  MAX_BIRDS_OPTION="-m $$MAX_BIRDS"; \
	fi; \
	perl fetch-bird-images.pl -a $@ $$MAX_BIRDS_OPTION --manifest $<

clean:
	rm -f autocomplete-example.tar.gz

realclean:
	rm -f images/*.png
	rm -f images/jpg/*.jpg
	rm -f $(AUTOCOMPLETE)
