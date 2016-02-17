all: ard.pdf

ard.pdf: images/*.png

%.pdf: %.md
	pandoc $< -o $@

clean:
	rm *.pdf
