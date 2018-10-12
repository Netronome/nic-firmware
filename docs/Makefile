# Makefile for Corenic documentation
#
#
ifeq (,$(DOC_DIR))
    DOC_DIR := '.'
endif

# You can set these variables from the command line.
SPHINXOPTS    =
SPHINXBUILD   = sphinx-build
SPHINXPROJ    = corenic
BUILDDIR      = build
PAPER         =

# Internal variables.
PAPEROPT_a4     = -D latex_paper_size=a4
PAPEROPT_letter = -D latex_paper_size=letter
ALLSPHINXOPTS   = -d $(BUILDDIR)/doctrees $(PAPEROPT_$(PAPER)) $(SPHINXOPTS)
# the i18n builder cannot share the environment and doctrees with the others
I18NSPHINXOPTS  = $(PAPEROPT_$(PAPER)) $(SPHINXOPTS) $(SOURCEDIR)

.PHONY: all-doc
all-doc : user-guide user-guide-spelling

.PHONY: help-docs
help-docs:
	@echo "Please use \`make <target>' where <target> is one of"
	@echo "  user-guide       		to make corenic user guide"
	@echo "  user-guide-spelling       	to spellcheck corenic user guide"

.PHONY: clean
clean:
	rm -rf $(BUILDDIR)/*

.PHONY: user-guide
user-guide:
	$(SPHINXBUILD) -b singlehtml $(ALLSPHINXOPTS) $(DOC_DIR)/user-guide  $(BUILDDIR)/user-guide
	@echo
	@echo "Build finished. The HTML pages are in $(BUILDDIR)/user-guide."

.PHONY: user-guide-spelling
user-guide-spelling:
	$(SPHINXBUILD) -b spelling $(ALLSPHINXOPTS) $(DOC_DIR)/user-guide $(BUILDDIR)/user-guide
	@echo
	@echo "Spellcheck in the sources finished, look at the " \
	                  "results in $(BUILDDIR)/user-guide/output.txt."

