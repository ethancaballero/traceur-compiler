RUNTIME_SRC = \
  src/runtime/runtime.js \
  src/runtime/url.js \
  src/runtime/modules.js \
  src/runtime/polyfill-bootstrap.js
SRC = \
  $(RUNTIME_SRC) \
  src/traceur-import.js
TPL_GENSRC = \
  src/outputgeneration/SourceMapIntegration.js
GENSRC = \
  $(TPL_GENSRC) \
  src/codegeneration/ParseTreeTransformer.js \
  src/syntax/trees/ParseTreeType.js \
  src/syntax/trees/ParseTrees.js \
  src/syntax/ParseTreeVisitor.js
TPL_GENSRC_DEPS = $(addsuffix -template.js.dep, $(TPL_GENSRC))

TFLAGS = --

RUNTIME_TESTS = \
  test/unit/runtime/System.js \
  test/unit/runtime/Loader.js

UNIT_TESTS = \
	test/unit/codegeneration/ \
	test/unit/node/ \
	test/unit/semantics/ \
	test/unit/syntax/ \
	test/unit/system/ \
	test/unit/util/

TESTS = \
	test/node-nodejs-test.js \
	test/node-requirejs-test.js \
	test/node-feature-test.js \
	$(RUNTIME_TESTS) \
	$(UNIT_TESTS)

GIT_BRANCH = $(shell git rev-parse --abbrev-ref HEAD)

build: bin/traceur.js wiki

min: bin/traceur.min.js

# Uses uglifyjs to compress. Make sure you have it installed
#   npm install uglify-js -g
ugly: bin/traceur.ugly.js

test-runtime: bin/traceur-runtime.js $(RUNTIME_TESTS)
	@echo 'Open test/runtime.html to test runtime only'

test: bin/traceur.js bin/traceur-runtime.js test/test-list.js test/requirejs-compiled test/nodejs-compiled
	node_modules/.bin/mocha --ignore-leaks --ui tdd --require test/node-env.js $(TESTS)

test/unit: bin/traceur.js bin/traceur-runtime.js
	node_modules/.bin/mocha --ignore-leaks --ui tdd --require test/node-env.js $(UNIT_TESTS)

test/nodejs: test/nodejs-compiled
	node_modules/.bin/mocha --ignore-leaks --ui tdd test/node-env.js test/node-nodejs-test.js

test/requirejs: test/requirejs-compiled
	node_modules/.bin/mocha --ignore-leaks --ui tdd test/node-env.js test/node-requirejs-test.js

test/features: bin/traceur.js bin/traceur-runtime.js test/test-list.js
	node_modules/.bin/mocha --ignore-leaks --ui tdd --require test/node-env.js test/node-feature-test.js

test-list: test/test-list.js

test/test-list.js: force
	@git ls-files -o -c test/feature | node build/build-test-list.js > $@

# TODO(vojta): Trick make to only compile when necesarry.
test/nodejs-compiled: force
	node src/node/to-nodejs-compiler.js test/nodejs test/nodejs-compiled

test/requirejs-compiled: force
	node src/node/to-requirejs-compiler.js test/requirejs test/requirejs-compiled

boot: clean build

clean: wikiclean
	@rm -f build/compiled-by-previous-traceur.js
	@rm -f build/dep.mk
	@rm -f $(GENSRC) $(TPL_GENSRC_DEPS)
	@rm -f test/test-list.js
	@rm -rf test/nodejs-compiled/*
	@rm -rf test/requirejs-compiled/*
	@rm -f bin/*
	@git checkout -- bin/
	@mv bin/traceur.js build/previous-commit-traceur.js

initbench:
	rm -rf test/bench/esprima
	git clone https://github.com/ariya/esprima.git test/bench/esprima
	cd test/bench/esprima; git reset --hard 1ddd7e0524d09475
	git apply test/bench/esprima-compare.patch

bin/%.min.js: bin/%.js
	node build/minifier.js $^ $@

bin/traceur-runtime.js: $(RUNTIME_SRC)
	./traceur --out $@ $(TFLAGS) $^

bin/traceur-bare.js: src/traceur-import.js build/compiled-by-previous-traceur.js
	./traceur --out $@ $(TFLAGS) $<

concat: bin/traceur-runtime.js bin/traceur-bare.js
	cat $^ > bin/traceur.js

bin/traceur.js: build/compiled-by-previous-traceur.js
	@cp $< $@; touch -t 197001010000.00 bin/traceur.js
	./traceur --out bin/traceur.js $(TFLAGS) $(SRC)

# Use last-known-good compiler to compile current source
build/compiled-by-previous-traceur.js: build/previous-commit-traceur.js $(SRC) build/dep.mk
	@cp build/previous-commit-traceur.js bin/traceur.js
	./traceur --out $@ $(TFLAGS) $(SRC)

build/previous-commit-traceur.js:
	mv bin/traceur.js build/traceur.js
	git checkout -- bin/traceur.js
	mv bin/traceur.js build/previous-commit-traceur.js
	mv build/traceur.js bin/traceur.js

debug: build/compiled-by-previous-traceur.js $(SRC)
	./traceur --debug --out bin/traceur.js --sourcemap $(TFLAGS) $(SRC)

self: force
	mkdir -p build/node
	mv src/node/* build/node # Save in case of src diffs.
	git checkout -- src/node # Over-write with last-good node compiler front.
	-make debug              # Build with last-good node compiler front.
	mv build/node/* src/node # Restore possible src diffs.
	rmdir build/node         # Clean up.

# Prerequisites following '|' are rebuilt just like ordinary prerequisites.
# However, they don't cause remakes if they're newer than the target. See:
# http://www.gnu.org/software/make/manual/html_node/Prerequisite-Types.html
build/dep.mk: build/previous-commit-traceur.js | $(GENSRC) node_modules
	@cp build/previous-commit-traceur.js bin/traceur.js  # ` known-good compiler
	node build/makedep.js --depTarget build/compiled-by-previous-traceur.js $(TFLAGS) $(SRC) > $@

$(TPL_GENSRC_DEPS): | node_modules

src/syntax/trees/ParseTrees.js: \
  build/build-parse-trees.js src/syntax/trees/trees.json
	node $^ > $@

src/syntax/trees/ParseTreeType.js: \
  build/build-parse-tree-type.js src/syntax/trees/trees.json
	node $^ > $@

src/syntax/ParseTreeVisitor.js: \
  build/build-parse-tree-visitor.js src/syntax/trees/trees.json
	node $^ > $@

src/codegeneration/ParseTreeTransformer.js: \
  build/build-parse-tree-transformer.js src/syntax/trees/trees.json
	node $^ > $@

unicode-tables: \
	build/build-unicode-tables.js
	node $^ > src/syntax/unicode-tables.js

%.js: %.js-template.js
	node build/expand-js-template.js --nolint=^node_modules $< $@

%.js-template.js.dep: | %.js-template.js
	node build/expand-js-template.js --deps $| > $@

NPM_INSTALL = npm install --local && touch node_modules

node_modules/%:
	$(NPM_INSTALL)

node_modules: package.json
	$(NPM_INSTALL)

bin/traceur.ugly.js: bin/traceur.js
	uglifyjs bin/traceur.js --compress -m -o $@

WIKI_OUT = \
  test/wiki/CompilingOffline/out/greeter.js

wiki: $(WIKI_OUT)

wikiclean:
	@rm -rf test/wiki/CompilingOffline/out

test/wiki/CompilingOffline/out/greeter.js: test/wiki/CompilingOffline/greeter.js
	./traceur --out $@ $^


.PHONY: build min test test-list force boot clean distclean unicode-tables

-include build/dep.mk
-include $(TPL_GENSRC_DEPS)
-include build/local.mk
