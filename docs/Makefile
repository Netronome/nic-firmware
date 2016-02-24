all: ard.pdf

ard.pdf: ard/ard.md ard/images/*.png
	@echo Building ard.pdf
	@(cd ard ; pandoc ard.md -o ../ard.pdf)

clean:
	rm -f *.pdf
