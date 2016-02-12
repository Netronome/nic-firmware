Coding Style
============

This file describes the coding style used in the C and Python files in
this repository.  It is informed by a number of sources,
including the Linux Kernel coding style, the Open vSwitch coding style
the Java Programming Language code conventions, and the Python PEP-8
describing good Python coding practices.

## Rationale

A coding style and coding conventions are important to a software
engineering project for a number of reasons:

* The software is written once and maintained forever.

* Maintenance is predominantly performed by reading code that was
authored by others.

* Consistent readability, then, reduces the time required for code
  maintenance.

## Structure of the Coding Style Document

* Directory structure

* Basic source file style

* C header and source file style in detail

* Micro-C specific details

# Directory Structure

Each directory must contain a README.md file

Firmware (code for the NFP) is stored and built in the firmware
subdirectory; host code (code for the main CPU) is stored and built in
the host subdirectory.

The scripts subdirectory contains scripts required to run
applications, and to assist the build and debug process.

The python subdirectory contains Python code that for applications,
and for debugging.

Documentation is in the doc subdirectory.

## Scripts subdirectory

The scripts subdirectory contains scripts that are accessible from the
command line or Makefiles to help reduce typing for the developer.

## Python subdirectory

The python subdirectory contains scripts for use in the NFP debug
environment, scripts to enable data analysis and plotting, and various
utility scripts.

Python is the preferred application scripting language.

## Firmware subdirectory

The firmware subdirectory contains app and lib subdirectories. The app
directory contains application code, and the lib contains more generic
libraries

### Firmware/lib subdirectory

This directory contains subdirectories for libraries. Each
subdirectory has a number of header files, included with
<libname/header.h>, and a lib<libname>.c file. Further, there is a _c
subdirectory which contains C code included by the lib<libname>.c
file. The header file is included in firmware C source, and the
lib<libname>.c is included as one of the firmware libraries in the
MicroC build.

The base library used for much of the application code is nfp; this
includes basic functions for reading and writing memories in the NFP,
and simple interactions. More complicated libraries which provide
higher level functionality may be provided also. For example, the
'sync' library provides context, ME and island synchronization for
initialization staging.

### Firmware/app subdirectory

An application in MicroC generally requires some common code and some
toplevel ME-specific source code. An application will then have an
<application>_lib.c file and <application>_lib.h file, which will
contain the MicroC for all the threads in the application. Then there
will be further <application>_<me_aspect>.c files which include the
<application>_lib.h file and a 'main', which invokes appropriate
toplevel thread functions.

## Host subdirectory

The host subdirectory contains source code for the host CPU,
Makefiles, and the build area for host code.

### Host/src subdirectory

The source for applications and libraries is kept in host/src, with no
further subdirectories.

### Host/obj subdirectory

The compiled C object files are buil in host/obj.

### Host/bin subdirectory

The linked host binaries are built into host/bin.

# Basic Source File Style

## File naming

Filenames must be descriptive, and consistent. Where multiple files
are used for the same application they should use a common prefix. For
firmware, an application initial-CSR setting file should be
<application>_init.uc.

## Basic Source File Layout

No source code line should exceed 79 characters; this permits, for
example, emacs 80-character windows to be used to view and edit the
code.

Use four spaces for an indent; particularly, also, do not use tabs for
indentation (this is *not* the Linux kernel...)

Should a source file reach a length that makes it difficult to
maintain, form feeds (control+L) may be used to split it in to logical
sections. Each section must start with a comment identifying it.

## Preprocessor directives

The `#if` and `#ifdef` directives must be used sparingly. When used
within source of a function they should surround a function; this
enables simpler checking of dependencies of different preprocessor
build options. It is much more preferable to use compile-time
constants and regular `if` statements for code, as the compiler will
perform all relevant checking before eliminating any unrequired code.

Code must not be excluded from compilation with `#if 0` directives. If
code needs to be removed from a file, it should be removed by
deletion.

## Function, Structures, Variable and Macro Naming

Descriptive names should be used for functions, structures and
variables. The name should describe the purpose of the object.

All objects should use lower case, except for macros and enumerations
which must use upper case.

Further:

* All externally visible objects (for example, external callable
functions) defined within a module are viewed as being part of the
namespace of the nfp-common project; as such they should be prefixed
with the same short prefix, ending with an underscore, specific to
that module.

 * As the module is explicitly viewed as being in the namespace of
   `nfp-common` the prefix must not include `nfp`; this would just be
   unnecessary.

 * Members of an externally visible object (e.g. elements of a
   structure, parameters of a function) are viewed as being within the
   namespace of the object, and so they must not include the prefix in
   their names.

* Use underscores to separate words.

* The name of an array must be a plural; the name of a (non-array)
  element of an array must be plural.

* Control variables should be positive; so `multiple_of_three` is
  good, but `not_multiple_of_three` should not be used.

* A name starting with `num_` is used for 'number of', and not
  `n_`. Arrays have a size, and a variable containing the size of an
  array should use `size` and not `length`. Strings and packets, for
  example, stored within an array, have a `length`

## Comments and Documentation

Source files must be commented to describe the purpose and general
operation of the elements of the code, including structures, macros,
variables and functions.

Comments must be written as English sentences, starting with a capital
letter and ending in a full stop.

Comments may fit on a single line, starting with `/*` and ending with
`*/`, and can follow code.

Larger comments must be block comments following the OVS and
(non-network driver) Linux kernel style, starting with a single line
containing only indentation followed by `/*`; continued with lines
containing one extra space of indentation followed by `* ` followed by
comment; terminated with the original indentation followed by
`*/`. For example:

    /*
     * Larger comments must be block comments starting with a single
     * line containing indentation and comment start marker, with
     * following lines containing the comment, terminating with a
     * final line with a comment end marker
    */

Every function, and every variable declared at the top level
(i.e. outside a function) and every type definition (structure, union,
typedef) must be preceded by a comment describing the purpose or use
of the object, starting with the name of the function or
structure. These comments must use a double asterisk, and must start
at the beginning of a line. For example:

    /** packet_capture_pkt_rx_dma
     * Handle packet received by CTM; claim next part of MU buffer, DMA
     * the packet in, then pass on to work queue and free the packet
     *
     */

When code is incomplete, it should be commented with a line comment
starting `/* XXX` and with appropriate further wording.

When code is known to be broken for some subset of circumstances, it
should be commented with a line comment starting with `/* FIXME` and
with appropriate further wording.

# C Header and Source File Structure In Detail

## C Header File Structure

C header files must have the following structure:

1. The copyright notice

2. Brief module API documentation

3. An 'include-once' #include guard

4. Any #include's required by the header file

5. Macros

6. Externally-visible type definitions

7. Variable declarations

8. Function declarations.

9. Close of #include guard

The include guard for MicroC should be name _<lib>__<hdr>__H_. The
include guard for a MicrocC application header file should be <app>_H.

Open issues currently are memory pool declarations and potentially
anything for threading.

### Example of a #include Guard

This is of the form

    #ifndef PKT_CAP_H
    #define PKT_CAP_H 1

    ...

    #endif /* PKT_CAP_H */

### Restrict Structure and Function Definitions

Data structures that should be opaque to the including source file
should not be defined in a header file unless absolutely required; if
an opaque structure pointer is required for function declarations,
then a struct tag declaration should be used. For example:

  struct fred;
  extern struct fred *make_fred( void );

In some cases the opaque type may need to be defined, particularly if
the header file declares inline functions which operate on the members
of the (externally opaque) structure.

### Standalone Nature

The inclusion of a header file by some C source file should not
depend on a previous header file include in that C source
file. Hence every header file should include the header files that
it depends upon.

Combined with the requirement to restrict structure and function
definitions, this may mean that a struct tag declaration is used in
preference to a header file inclusion (or list of inclusions) which
would enable the structure to be declared fully.

## C Source File Structure

C source files must have the following structure:

1. The copyright notice

2. Module / source file documentation

3. Includes

4. Macros

5. Structure definitions

6. Static function declarations.

7. Static variable declarations.

8. Memory initializations (micro-C only)

9. Function definitions.

### Module / Source File Documentation

This must be a block comment that explains the purpose of the code in
the file, and how it relates to other code in the module in other
source files.

If the source file is the main or top level component of a module then
this documentation should first describe the purpose of the module,
and how it relates to other modules in the project.

### Includes

The `#include` directives should appear in the following order:

1. The module's own headers, if any. This helps ensure that module
headers are not dependent on any other include files (see the header
file above).

2. Standard C library headers.

3. Other system headers.

4. Headers for other modules from the project that are required by the
   source file.

### Static function decalartions

This section is only required if the file includes static function
definitions after the externally visible function definitions. When
this section is included, the static function declarations should be
grouped logically with blank lines between the groups, and with a
comment preceding each group.

### Static variable declarations

Non-constant static variables should not be used in host code in
general, as they make it difficult to use code in more than one
place. However, in micro-C they may be used more freely as multiple
use of modules is explicit and not dynamic, as it is in host code. The
micro-C compiler also optimizes out any unused static register
variables, a common occurrence when a C module library source file
includes functions for different microengines within an application.

### Memory initializations

Micro-C may include memory initializations and possibly resource
allocations.

### Function definitions

A predictable order of function definitions with a file helps
readability. Therefore static function definitions should be included
first followed by externally visible functions.

The static functions ideally should be grouped in functionality and
such that function declarations are not required.

Externally visible functions should appear in the same order
as they are declared in the header file.

## C Preprocessor Usage

The C preprocessor is both a friend and an enemy to the coder; it
should be used sparingly.

C preprocessor macros should be used as little as possible as they
obfuscate code.

Use enumerations instead of macros, where possible, for constant
values.

Use (static) inline functions instead of function macros, where
possible.

When a procedural macro is required and it contains multiple statements
use the construct 'do { ... } while (0)' to wrap the statements

Protect macro arguments by placing () around them when used.

## Function Declarations / Protoypes

All function declarations must include a complete prototype, including
parameters and their types. The return type and the function name
must be placed on the same line. For example:

    __intrinsic void cls_write(__xwrite void *data, __cls void *addr,
                               int ofs, const size_t size);


## Function Definitions

Function definitions must be written out differently to function
declarations, separating the return value from the function name and
parameters. The braces that surround the code for the function must be
on their own lines with no indentation. For example:

    __intrinsic void
    cls_write(__xwrite void *data, __cls void *addr, int ofs,
              const size_t size)
    {
    ...
    }

Furthermore, each function definitions must be preceded by a
non-indented block comment starting with a double-asterisk `/**` and
the name of the function. The comment should briefly describe the
function's purpose and return value, then the purpose of each
parameter, any side-effects (updates to data structures, be they
static or referenced by a parameter) and if sensible a more detailed
breakdown of the operation of the function. For example:

    /** cls_write
     * Write a number of words of data to the local cluster scratch
     *
     * @param data   Transfer registers to write
     * @param addr   32-bit CLS island-local address
     * @param ofs    Offset from address
     * @param size   Size in bytes to write (must be multiple of 4)
     *
     */

In the documentation comment for the function a parameter should be
referenced with single quotes (e.g. `param`) or using `@param` when
its purpose is being given.

### Function Parameter Order

The preferred order of parameters for most code is:

    1. The main object being manipulated by the function, akin to the
       'self' reference in a Python class call or 'this' in a C++
       object method.
   2. Input-only parameters
   3. Output or input-output parameters

For example:

    int nfp_get_rtsym_cppid(struct nfp *nfp, const char *sym_name,
                            struct nfp_cppid *cppid);

### Function Parameter Checking

Low level functions should in general not check their parameters for
'correctness'; this should be performed a higher levels for the sake
of performance, and for the ease of debugging. Externally visible
functions will generally fall under the 'higher level' category.

In micro-C there should be no checking; all functions are 'lower level'.

Destructor or freeing functions which must take a pointer to an object
to free must be defined to accept a NULL pointer as 'correct', and so
must check the pointer before issuing (e.g.) a call to 'free'.

## C Code Blocks

### Variable Declarations

A basic block should not include more than 5 to 10 variable
declarations. If more seem to be required, then the functionality
performed by the basic block should be split in to separate functions
or multiple basic blocks.

Because of this limit it is sensible to use a single variable
declaration per line, with a comment. For example:

```
    char *nffw;    /* Firmware buffer to load, filled from filename */
    int nffw_size; /* Size of firmware buffer and firmware */
    int err;       /* Error returned by NFP functions */
```

### General practices

#### Indentation

Indentation must be by spaces, with an indentation level being 4
(four) spaces.

#### Braces

Use BSD-style brace placement:

    if (a()) {
        b();
        d();
    }

Single statements may be enclosed in braces if it improves
readability:

    if (a > b) {
        return a;
    } else {
        return b;
    }

#### Statements

Write only one statement per line.

### Return statements

As `return` is not a function, do not put follow it with a bracketed
expression unless it is to break up the expression while maintaining
indentation.

### If, While and For statements

Put a space between `if`, `while`, `for`, etc. and the expressions
that follow them.

Avoid assignments inside `if` and `while` conditions.

An infinite loop must be written as `for (;;)`

Where an `if` statement includes an `else` clause, ensure that the
standard operational code flow (if there is one) is in the `if`
branch with the exceptional code flow in the `else` clause.

### Switch statements

Indent `switch` statements like this:

    switch (action) {
    case KOBJ_ADD:
        return "add";
    case KOBJ_REMOVE:
        return "remove";
    case KOBJ_CHANGE:
        return "change";
    default:
        return NULL;
    }
    
  "switch" statements with very short, uniform cases may use an
abbreviated style:

    switch (code) {
    case  1: return "add";
    case  4: return "remove";
    case 16: return "change";
    default: return NULL;
    }

### Expressions

Expressions should include spaces in common with OVS, the linux
kernel, and many other coding styles:

* No spaces after unary operators ! ~ ++ -- + - * &

* No spaces on either side of the . and -> structure accessor operators

* One space on each side of most binary and ternary operators =  +  -
  <  >  *  /  %  |  &  ^  <=  >=  ==  !=  ?  : && || += -= *= /= %= &=
  ^= |= <<= >>=

* No spaces before unary preincrement/predecrement operators ++ --

* No spaces after brackets () [], unless heavily nested, when common
  sense should be used to visually group expression elements

Only use the comma operator in for statements.

#### Use of Parentheses

Use parentheses whenever their might be confusion as to operator
precedence. Remember that the author may not be confused
by the code, but the use of parentheses is for the reader and to
prevent any confusion they might have in skimming the code.

Use parentheses to enhance readability and ease of indent in an editor
when an expression is split across multiple lines. For example

    cmd.cpp_addr_lo = ((mu_buf_dma_desc->mu_base_s8 << 8) +
                        dma_start_offset);

#### Breaking lines in expressions

When an expression needs to be broken into multiple lines:

* Ensure the expression is within top-level parentheses

* Break at the highest level of expression as is reasonable

* Break after an operator

* Indent the new line to the level of expression it matches in the
  lines above.

# Micro-C specific details

Micro-C is always to be treated as an embedded programming
language. Althought the language is capable of automatically inserting
memory transactions to read/write the various memory hierarchies to
get structures, these transactions are hard to budget for and may lead
to code that runs with lower performance than expected. So a number of
coding style rules should be followed to ensure performance.

## Memory transactions

All memory transactions should be explicit. This may be performed with
use of library functions such as cls_read() or through embedded
assembler (although the former is far preferred).

To avoid the compiler generating implicit memory transactions, the
first rule is to explicitly copy structures in to registers; the
second is to ensure that -Qspill=7 is used for compilation.

## Standard C library functions

The standard C library functions should not be used.

## Base types

The types `uint32_t` and `uint64_t` should be used where precise size
integers are required (for example, in structures or variables that
are transferred to or from memory). `int` may be used where the size
is less critical. `stdint.h` is required for the `uint` types.

## Structures

Structures should be used wherever possible for data that needs to be
collated, in particular for transfers to and from memory. As with
standard coding style, 'typedef' should not be used.

### Bit-fields

Packed structures may result in smaller memory footprints and lower
bus utilization, and as micro-C is for embedded code they are highly
desirable. All bit-fields should be 'unsigned int' (not `int`).

The packing operates best on a microengine when the structures start
on 8-bit boundaries, do not cross 32-bit boundaries, and even more so
in not crossing 64-bit boundaries.

Frequently a anonymous union of a structure of elements and a raw
array of `uint64_t` or `uint32_t` is defined so that the structure can
be simply cleared.

## Embedded assembler

Embedded assembler should be used sparingly, and should ideally be hidden
within __intrinsic functions.

There are four circumstances when embedded assembler may be
justified:

* To permit use of the .init and .alloc directives that are not
  available in the micro-C compiler
  
* To encode an explicit CPP command instruction

* To use microengine instructions that are not available through the
 compiler (such as CRC and FFS)

* To optimize code when the micro-C compiler cannot be persuaded to
 get anywhere near the performance of hand-coded assembler
 
It is exceptionally rare that the micro-C compiler cannot be persuaded
 to produce adequate code, and optimizations in assembler must be
 thoroughly justified.

