Introduction
-------------

Crucible is a language-agnostic library for performing forward
symbolic execution of imperative programs.  It provides a collection
of data-structures and APIs for expressing programs as control-flow
graphs.  Programs expressed as CFGs in this way can be automatically
explored by the symbolic execution engine.  In addition, new data
types and operations can be added to the symbolic simulator by
implementing fresh primitives directly in Haskell.  Crucible relies on
an underlying library called What4 that provides formula
representations, and connections to a variety of SAT and SMT solvers
that can be used to perform verification and find counterexamples to
logical conditions computed from program simulation.

Crucible has been designed as a set of Haskell packages organized so
that Crucible itself has a minimal number of external dependencies,
and functionality independent of crucible can be separated into sub-libraries.

Currently, the repository consists of the following Haskell packages:

 * **`what4`** provides a library for formula representation and
   communications with satisfiability and SMT solvers (e.g., Yices and Z3).
 * **`what4-abc`** provides additional solver support for the ABC
   circuit synthesis library, which has strong support for equality
   and satisfiability queries involving boolean circuits.
 * **`what4-blt`** provides additional solver support for the BLT
   solver, which specializes in bounded integer linear problems.

 * **`crucible`** provides the core Crucible definitions, including the
   symbolic simulator and control-flow-graph program representations.
 * **`crucible-llvm`** provides translation and runtime support for
   executing LLVM assembly programs in the Crucible symbolic simulator.
 * **`crucible-jvm`** provides translation and runtime support for
   executing JVM bytecode programs in the Crucible symbolic simulator.
 * **`crucible-saw`** provides functionality for generating
   SAW Core terms from Crucible Control-Flow-Graphs.
 * **`crucible-syntax`** provides a native SExpression based concrete
   syntax for crucible programs.  It is useful for being able to
   directly interact with the core Crucible simulator without bringing
   in issues related to the translation of other front-ends (e.g. the
   LLVM translation).  It is primarily intended for the purpose of
   writing test cases.
 * **`crux`** provides common support libraries for running the
   crucible simulator in a basic "all-at-once" use mode for simulation
   and verification.  This includes most of the setup steps required
   to actually set the simulator off and running, as well as
   functionality for collecting and discharging safety conditions and
   generated assertions via solvers.  Both the `crucible-c` and `crucible-jvm`
   executables are thin wrappers around the functionality provided
   by `crux`.

In addition, there are the following library/executable packages:

 * **`crucible-c`**, a standalone frontend for executing C programs
   in the crucible symbolic simulator.  The front-end invokes `clang`
   to produce LLVM bitcode, and runs the resulting programs using
   the `crucible-llvm` language frontend.  Programs interact directly
   with the symbolic simulator using the protocol established for
   the [SV-COMP][sv-comp] competition.

[sv-comp]: https://sv-comp.sosy-lab.org

 * **`crucible-jvm`**, also contains an executable for directly
   running compiled JVM bytecode programs, in a similar vein
   to the `crucible-c` package.

 * **`crucible-server`**, a standalone process that allows constructing
   and symbolically executing Crucible programs via [Protocol Buffers][pb].
   The crucible-server directory also contains a Java API for
   connecting to and working with the `crucible-server`.

[pb]: https://developers.google.com/protocol-buffers/ "Protocol Buffers"


The development of major features and additions to `crucible` is done
in separate branches of the repository, all of which are based off
`master` and merge back into it when completed. Minor features and bug
fixes are done in the `master` branch. Naming of feature branches is
free-form.

Each library is BSD-licensed (see the `LICENSE` file in a project
directory for details).

Quick start
-------------
To fetch all the latest git versions of immediate dependencies of
libraries in this repository, use the `scripts/build-sandbox.sh` shell
script; alternately, you can manually invoke the git commands to
initialize and recursively update submodules.  You will find it most
convenient to setup public-key login for GitHub before you perform
this step.

Now, you may use either `stack` or `cabal new-build` to compile the
libraries, as you prefer.

```
ls stack-ghc-*.yaml
# Choose the GHC version you prefer
ln -s stack-ghc-<version>.yaml stack.yaml
./scripts/build-sandbox.sh
stack setup
stack build
```

```
./scripts/build-sandbox.sh
cabal update
cabal new-configure
cabal new-build all
```

Alternately, you can target a more specific sub-packge instead of `all`.

If you wish to build `crucible-server` (which will be built if you
build all packages, as above), then the build depends on having `hpb`
in your path. After fetching the dependencies, this can be arranged by
entering `dependencies/hpb/` and running the following commands:

```
cabal sandbox init
cabal install --dependencies-only
cabal install
cp ./cabal-sandbox/bin/hpb ⟨EXE_PATH⟩
```
where `⟨EXE_PATH⟩` is a directory on your `$PATH`.
