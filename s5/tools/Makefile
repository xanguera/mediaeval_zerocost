#Compiles MITLM, including the patching for OSX

#detect if we are compiling in OSX
UNAME_S := $(shell uname -s)
OPTIONS :=
ifeq ($(UNAME_S),Darwin)
        OPTIONS := -stdlib=libstdc++
endif

#for now we do not need mitlm in the server
#all: openfst mitlm phonetisaurus
all: mitlm

mitlm: FORCE
	tar -xvzf mitlm-0.4.1.tar.gz
	ln -s mitlm-0.4.1 mitlm
	#patch the package
	patch -p0 < mitlmPatch.patch
	cd mitlm-0.4.1; \
	./configure CXXFLAGS=$(OPTIONS); \
	make -j 8

FORCE:

clean:
	rm -Rf mitlm-0.4.1
