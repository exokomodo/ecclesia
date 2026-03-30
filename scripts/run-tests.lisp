#!/usr/bin/env -S sbcl --script
;;;; scripts/run-tests.lisp — run Ecclesia unit tests

(require 'asdf)
(pushnew (truename "./") asdf:*central-registry* :test #'equal)
(asdf:load-system :ecclesia/test)
