# Serialization Directives Specification

**Source**: Extracted from `pp_ser.py` (SerialBox Fortran preprocessor)
**Version**: 0.1 (original author: Oliver Fuhrer, MeteoSwiss, 2014)

---

## 1. Overview

The serialization preprocessor (`pp_ser`) expands `!$SER` directives embedded in
Fortran source code into calls to the SerialBox Fortran serialization API
(`m_serialize` module and `utils_ppser` utility module). The preprocessor
operates on `.f90`, `.f`, `.f03`, `.inc`, and `.incf` files.

### 1.1 Processing Model

The preprocessor uses a **two-pass** strategy:

1. **Analysis pass**: Scans the file to collect all serialization API calls
   that will be required. This information is used to generate correct
   `USE` import statements.
2. **Generation pass**: Expands each directive into the corresponding Fortran
   code, inserting `USE` statements and `#ifdef`/`#endif` guards as needed.

### 1.2 Scope Tracking

The preprocessor tracks Fortran scoping units (`MODULE`, `PROGRAM`,
`SUBROUTINE`, `FUNCTION`) to determine where to insert `USE` statements:

- If a `MODULE` or `PROGRAM` statement is encountered, the `USE` statement is
  inserted immediately after it, and no further `USE` statements are generated
  for contained subroutines/functions within that module.
- If standalone `SUBROUTINE` or `FUNCTION` statements are encountered (outside
  a module), the `USE` statement is inserted after the procedure header
  (including any continuation lines).

---

## 2. General Syntax

### 2.1 Directive Prefix

All directives begin with the prefix `!$SER` (case-insensitive). The `!`
character makes the directive appear as a Fortran comment to standard compilers.

```
!$SER <KEYWORD> [arguments...]
```

The prefix recognition regex is:

```
^ *!\$ser *(.*)$
```

This allows optional leading whitespace before `!$SER` and optional whitespace
between `!$SER` and the keyword.

### 2.2 Case Insensitivity

All directive keywords and their abbreviations are **case-insensitive**.
Arguments (field names, variable names, key-value pairs) preserve their
original case as written in the source.

### 2.3 Line Continuation

Directives that span multiple lines use `&` as a continuation character:

- The initial line ends with ` &` (space followed by ampersand):
  ```
  !$SER DATA field1=var1 field2=var2 &
  ```
- Continuation lines use the prefix `!$SER&` (with optional leading whitespace):
  ```
  !$SER&     field3=var3 field4=var4 &
  !$SER&     field5=var5
  ```
- The final continuation line does **not** end with `&`.

The continuation prefix `!$SER&` is stripped and replaced with a single space
before the arguments are parsed. Trailing `&` characters and surrounding
whitespace are stripped from continued lines.

Continuation detection regex (initial line):
```
^ *!\$ser *(.*) & *$
```

Continuation prefix regex (subsequent lines):
```
^ *!\$ser& *
```

### 2.4 Argument Tokenization

After the keyword, arguments are tokenized by splitting on whitespace, with
respect for quoted strings (both single and double quotes):

```regex
((?:[^ "']|"[^"]*"|'[^']*')+)
```

This ensures that spaces inside quoted strings are preserved as part of a
single token.

### 2.5 Common Argument Grammar

Most directives parse their arguments using a shared argument parser that
classifies each token (after the keyword) into one of three categories:

1. **Positional arguments** (`dirs`): Tokens that do not contain `=`.
2. **Key-value pairs** (`keys`, `values`): Tokens of the form `key=value`.
   Exactly one `=` must be present.
3. **IF clause**: The keyword `IF` (case-insensitive) followed by exactly one
   token representing a Fortran logical expression. The `IF` clause must be the
   **last** argument on the directive line.

```
!$SER KEYWORD [positional...] [key=value...] [IF condition]
```

Rules:
- `IF` is recognized case-insensitively.
- Only **one** condition token is permitted after `IF`. If additional tokens
  follow, this is a syntax error.
- The condition token is a Fortran expression (e.g., `ntstep>0`,
  `allocated(v_in)`, `a==' this is a test '`).
- Positional arguments and key-value pairs can be freely interleaved before the
  `IF` keyword.

### 2.6 Preprocessor Guards (`#ifdef`)

When an ifdef symbol is configured (default: `SERIALIZE`), the preprocessor
wraps generated code in C preprocessor guards:

- Consecutive `!$SER` directive lines are grouped and wrapped in a single
  `#ifdef SERIALIZE` / `#endif` block.
- When a non-directive line appears after one or more directive lines, the
  `#endif` is emitted before that line.
- `USE` statements are similarly wrapped in `#ifdef` / `#endif`.

### 2.7 Empty Directives

A bare `!$SER` line (with no keyword or arguments) is valid and produces no
output, but it is still treated as a directive line for the purpose of
`#ifdef`/`#endif` grouping.

### 2.8 Source Annotation Comments

Each expanded directive is prefixed with a comment indicating the original
source file and line number:

```fortran
! file: <filename> lineno: #<line_number>
```

---

## 3. Directive Reference

### 3.1 INIT

**Keywords**: `INIT`, `INI`

**Purpose**: Initialize the serialization environment.

**Syntax**:
```
!$SER INIT <arg1> [<arg2> ...] [IF <condition>]
```

**Arguments**: All positional arguments (and key-value pairs) up to the
optional `IF` are passed directly as arguments to the initialization call.
These typically correspond to named Fortran arguments for the initialization
subroutine (e.g., `singlefile=.true.`).

**Generated code**:
```fortran
! file: <file> lineno: #<n>
[IF (<condition>) THEN]
PRINT *, '>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<'
PRINT *, '>>> WARNING: SERIALIZATION IS ON <<<'
PRINT *, '>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<'

! setup serialization environment
call ppser_initialize( &
           <arg1>, &
           <arg2>, &
           ...)
[ENDIF]
```

**API call**: `ppser_initialize`

**Example**:
```fortran
!$SER INIT singlefile=.true.
```

---

### 3.2 CLEANUP

**Keywords**: `CLEANUP`, `CLE`

**Purpose**: Finalize and clean up the serialization environment.

**Syntax**:
```
!$SER CLEANUP [<arg1> ...]
```

**Arguments**: All tokens after the keyword are passed as comma-separated
arguments to the finalize call. No `IF` clause parsing is performed by the
general argument parser for the arguments—all remaining tokens are passed
directly.

**Generated code**:
```fortran
! file: <file> lineno: #<n>
! cleanup serialization environment
call ppser_finalize(<arg1>,<arg2>,...)
```

**API call**: `ppser_finalize`

**Example**:
```fortran
!$SER CLEANUP
```

---

### 3.3 SAVEPOINT

**Keywords**: `SAVEPOINT`, `SAV`

**Purpose**: Create a named savepoint with optional metadata key-value pairs.

**Syntax**:
```
!$SER SAVEPOINT <name> [<key1>=<value1> ...] [IF <condition>]
```

**Arguments**:
- Exactly **one** positional argument: the savepoint name (a string identifier).
  More or fewer positional arguments is a syntax error.
- Zero or more key-value pairs providing savepoint metadata.
- Optional `IF` clause.

**Savepoint name handling**: By default, the savepoint name is passed as a
quoted string literal (`'name'`). When the `--sp-as-var` / `sp_as_var` option
is enabled, it is passed as a bare variable reference (no quotes).

**Generated code**:
```fortran
! file: <file> lineno: #<n>
[IF (<condition>) THEN]
call fs_create_savepoint('<name>', ppser_savepoint)
call fs_add_savepoint_metainfo(ppser_savepoint, '<key1>', <value1>)
call fs_add_savepoint_metainfo(ppser_savepoint, '<key2>', <value2>)
...
[ENDIF]
```

With `sp_as_var` enabled:
```fortran
call fs_create_savepoint(<name>, ppser_savepoint)
```

**API calls**: `fs_create_savepoint`, `fs_add_savepoint_metainfo`

**Example**:
```fortran
!$SER SAVEPOINT DycoreUnittest.DoStep-in LargeTimeStep=ntstep Test=Blabla IF ntstep>0
```

---

### 3.4 DATA

**Keywords**: `DATA`, `DAT`

**Purpose**: Serialize one or more data fields at the current savepoint. The
generated code dispatches between write, read, and read-with-perturbation modes
at runtime.

**Syntax**:
```
!$SER DATA <field1>=<expr1> [<field2>=<expr2> ...] [IF <condition>]
```

**Arguments**:
- Zero or more key-value pairs where:
  - `key` = the serialized field name (a string identifier)
  - `value` = a Fortran expression for the field data (e.g., `u(:,:,:,nnow)`)
- Optional `IF` clause.

**Computed field detection**: If a value expression contains any of the
characters/substrings `*`, `+`, `-`, `/`, or the word `merge`, the field is
considered *computed*. Computed fields are only written (serialized out); they
are **not** read back in read or read-perturb modes.

**Intent(in) handling**: Field variables that appear in `DATA` directives are
tracked. If they are declared with `INTENT(IN)` elsewhere in the source, the
preprocessor generates `#ifdef`/`#else`/`#endif` blocks that remove the
`INTENT(IN)` qualifier when serialization is active (since read mode needs to
write into these variables).

**Generated code**:
```fortran
! file: <file> lineno: #<n>
[IF (<condition>) THEN]
SELECT CASE ( ppser_get_mode() )
  CASE(0)
    call fs_write_field(ppser_serializer, ppser_savepoint, '<field1>', <expr1>)
    call fs_write_field(ppser_serializer, ppser_savepoint, '<field2>', <expr2>)
    ...
  CASE(1)
    call fs_read_field(ppser_serializer_ref, ppser_savepoint, '<field1>', <expr1>)
    ...
  CASE(2)
    call fs_read_field(ppser_serializer_ref, ppser_savepoint, '<field1>', <expr1>, ppser_zrperturb)
    ...
END SELECT
[ENDIF]
```

- `CASE(0)` = write mode
- `CASE(1)` = read mode (uses `ppser_serializer_ref`)
- `CASE(2)` = read-perturb mode (uses `ppser_serializer_ref` and `ppser_zrperturb`)

Computed fields (those containing `*`, `+`, `-`, `/`, or `merge`) are
**omitted** from the `CASE(1)` and `CASE(2)` blocks.

**API calls**: `fs_write_field`, `fs_read_field`, `ppser_get_mode`

**Example**:
```fortran
!$SER DATA u=u(:,:,:,nnow)
!$SER DATA v=v_in(:,:,:)+v_ref(:,:,:,nnow) IF allocated(v_in)
!$SER DATA u=u(:,:,:,nnew) u_nnow=u(:,:,:,nnow) v=v(:,:,:,nnew) IF ntstep>0
```

---

### 3.5 ACCDATA

**Keywords**: `ACCDATA`, `ACC`

**Purpose**: Identical to `DATA`, but additionally generates OpenACC data
transfer directives (`!$acc update host/device`) around the serialization calls.

**Syntax**:
```
!$SER ACCDATA <field1>=<expr1> [<field2>=<expr2> ...] [IF <condition>]
```

**Generated code**: Same as `DATA`, with the following additions:

- In write mode (`CASE(0)`), an `ACC_PREFIX UPDATE HOST (<expr>)` is generated
  **before** each `fs_write_field` call.
- In read mode (`CASE(1)`) and read-perturb mode (`CASE(2)`), an
  `ACC_PREFIX UPDATE DEVICE (<expr>)` is generated **after** each
  `fs_read_field` call (only for non-computed fields).
- If the `acc_if` option is set, each ACC update directive includes an
  `, IF (<acc_if>)` clause.

**Note**: The preprocessor emits `#define ACC_PREFIX !$acc` at the top of the
output file (unless disabled via the `--no-prefix` option), which makes
`ACC_PREFIX` expand to the OpenACC directive sentinel.

---

### 3.6 DATA_KBUFF

**Keywords**: `DATA_KBUFF`, `KBU`

**Purpose**: Serialize data fields using a k-buffer mechanism, which handles
vertical-level-specific serialization.

**Syntax**:
```
!$SER DATA_KBUFF k=<k_expr> k_size=<ksize_expr> <field1>=<expr1> [<field2>=<expr2> ...] [IF <condition>]
```

**Arguments**:
- **Required** key-value pairs: `k=<expression>` and `k_size=<expression>`.
- Additional key-value pairs for the fields to serialize.
- Optional `IF` clause.

**Generated code**:
```fortran
! file: <file> lineno: #<n>
[IF (<condition>) THEN]
    call fs_write_kbuff(ppser_serializer, ppser_savepoint, '<field1>', <expr1>, k=<k_expr>, k_size=<ksize_expr>, mode=ppser_get_mode())
    call fs_write_kbuff(ppser_serializer, ppser_savepoint, '<field2>', <expr2>, k=<k_expr>, k_size=<ksize_expr>, mode=ppser_get_mode())
    ...
[ENDIF]
```

The `k` and `k_size` key-value pairs are extracted and **not** passed as
regular field arguments; they are appended as named parameters to each call.

**API calls**: `fs_write_kbuff`, `ppser_get_mode`

---

### 3.7 MODE

**Keywords**: `MODE`, `MOD`

**Purpose**: Set the serialization mode at runtime.

**Syntax**:
```
!$SER MODE <mode> [IF <condition>]
```

**Arguments**: Exactly one positional argument specifying the mode.

**Predefined mode values**:

| Mode Name      | Numeric Value |
|----------------|---------------|
| `write`        | `0`           |
| `read`         | `1`           |
| `read-perturb` | `2`           |
| `CPU`          | `0`           |
| `GPU`          | `1`           |

If the mode argument matches one of these predefined names (case-sensitive),
its numeric value is substituted. Otherwise the argument is passed through
verbatim (assumed to be a Fortran variable or expression).

**Generated code**:
```fortran
! file: <file> lineno: #<n>
[IF (<condition>) THEN]
call ppser_set_mode(<numeric_value_or_expression>)
[ENDIF]
```

**API call**: `ppser_set_mode`

---

### 3.8 OPTION

**Keywords**: `OPTION`, `OPT`

**Purpose**: Set runtime options for the serialization framework.

**Syntax**:
```
!$SER OPTION <key1>=<value1> [<key2>=<value2> ...] [IF <condition>]
```

**Arguments**:
- **Only** key-value pairs are accepted. Positional arguments are a syntax
  error ("Must specify a name and a list of key=value pairs").
- Optional `IF` clause.

**Special handling**: For the `verbosity` key (case-insensitive), the values
`off` and `on` are automatically mapped to `0` and `1` respectively.

**Generated code**:
```fortran
! file: <file> lineno: #<n>
[IF (<condition>) THEN]
call fs_Option(<key1>=<value1>, <key2>=<value2>, ...)
[ENDIF]
```

**API call**: `fs_Option`

**Example**:
```fortran
!$SER OPTION verbosity=on
```

---

### 3.9 METAINFO

**Keywords**: `METAINFO`

**Purpose**: Attach metadata key-value pairs to the serializer object.

**Syntax**:
```
!$SER METAINFO [<varname1> ...] [<key1>=<value1> ...] [IF <condition>]
```

**Arguments**:
- **Positional arguments**: Treated as variable names where both the metadata
  key and the value are the variable name itself (i.e., the variable name is
  used as the string key and the variable is used as the value).
- **Key-value pairs**: The key becomes the metadata string key (quoted), and
  the value is the Fortran expression for the metadata value.
- Optional `IF` clause.

**Generated code**:
```fortran
! file: <file> lineno: #<n>
[IF (<condition>) THEN]
call fs_add_serializer_metainfo(ppser_serializer, "<key1>", <value1>)
call fs_add_serializer_metainfo(ppser_serializer, "<key2>", <value2>)
call fs_add_serializer_metainfo(ppser_serializer, "<varname1>", <varname1>)
...
[ENDIF]
```

Key-value pairs are processed first, then positional arguments.

**API call**: `fs_add_serializer_metainfo`

---

### 3.10 REGISTER

**Keywords**: `REGISTER`, `REG`

**Purpose**: Register a field's metadata (name, type, dimensions, halos) with
the serializer.

**Syntax**:
```
!$SER REGISTER <name> <type> [<shortcut_or_dims...>] [IF <condition>]
```

**Arguments**:
- At least **two** positional arguments are required: `<name>` and `<type>`.
  Fewer is a syntax error.
- The `<name>` is automatically single-quoted in the generated call.
- The `<type>` must be one of the recognized data types (see below).
- A third positional argument onward specifies the field dimensions, either
  as a shortcut code or as explicit dimension parameters.
- Key-value pairs are **not yet supported** for field metainfo and will produce
  an error if provided.
- Optional `IF` clause.

**Data Types**:

| Type keyword | Type string    | Length variable     |
|-------------|----------------|---------------------|
| `integer`   | `'int'`        | `ppser_intlength`   |
| `real`      | `ppser_realtype`| `ppser_reallength`  |

Any other type value (e.g., a variable like `fs_realtype`) is passed through
as the type string directly and is used as-is for both the type and length
parameters.

Wait — looking more carefully at the code: when the type is `integer` or
`real`, `dirs[1]` is replaced by a **two-element** list `[type_string, length_var]`.
For other values, the single value is kept, meaning only the type is provided
and the length/size parameters come from the subsequent positional arguments.

**Dimension Shortcuts**: If the third positional argument (after type
expansion) matches one of the predefined shortcut codes, it is expanded into
12 dimension/halo parameters, in the following order:
`iSize`, `jSize`, `kSize`, `lSize`, `iMinusHalo`, `iPlusHalo`, `jMinusHalo`,
`jPlusHalo`, `kMinusHalo`, `kPlusHalo`, `lMinusHalo`, `lPlusHalo`.

| Shortcut | Expansion |
|----------|-----|
| *(empty)* | `1 0 0 0 0 0 0 0 0 0 0 0` |
| `I`      | `ie 0 0 0 nboundlines nboundlines 0 0 0 0 0 0` |
| `J`      | `je 0 0 0 nboundlines nboundlines 0 0 0 0 0 0` |
| `J2`     | `je 2 0 0 nboundlines nboundlines 0 0 0 0 0 0` |
| `K`      | `ke 0 0 0 0 0 0 0 0 0 0 0` |
| `K1`     | `ke1 0 0 0 0 1 0 0 0 0 0 0` |
| `IJ`     | `ie je 0 0 nboundlines nboundlines nboundlines nboundlines 0 0 0 0` |
| `IJ3`    | `ie je 3 0 nboundlines nboundlines nboundlines nboundlines 0 0 0 0` |
| `IK`     | `ie ke 0 0 nboundlines nboundlines 0 0 0 0 0 0` |
| `IK1`    | `ie ke1 0 0 nboundlines nboundlines 0 0 0 1 0 0` |
| `JK`     | `je ke 0 0 nboundlines nboundlines 0 0 0 0 0 0` |
| `JK1`    | `je ke1 0 0 nboundlines nboundlines 0 1 0 0 0 0` |
| `IJK`    | `ie je ke 0 nboundlines nboundlines nboundlines nboundlines 0 0 0 0` |
| `IJK1`   | `ie je ke1 0 nboundlines nboundlines nboundlines nboundlines 0 1 0 0` |

Shortcut matching regex: `^($|[IJK][IJK1-9]*)` (case-insensitive after
uppercasing).

If the third argument is not a recognized shortcut, all dimension arguments
are passed through verbatim.

**Generated code**:
```fortran
! file: <file> lineno: #<n>
[IF (<condition>) THEN]
call fs_register_field(ppser_serializer, '<name>', <type>, <length>, <dim_params...>)
[ENDIF]
```

**API call**: `fs_register_field`

**Examples**:
```fortran
!$SER REG u fs_realtype IJK
!$SER REGISTER u fs_realtype ie je ke 1 nboundlines nboundlines nboundlines nboundlines 0 0 0 0
!$SER REGISTER dts fs_realtype
!$SER REGISTER nlastbound 'integer' 1
```

---

### 3.11 REGISTERTRACERS

**Keywords**: `REGISTERTRACERS`

**Purpose**: Register all tracer fields with the serialization framework.

**Syntax**:
```
!$SER REGISTERTRACERS
```

**Arguments**: None.

**Generated code**:
```fortran
! file: <file> lineno: #<n>
call fs_RegisterAllTracers()
```

**API call**: `fs_RegisterAllTracers`

---

### 3.12 ZERO

**Keywords**: `ZERO`, `ZER`

**Purpose**: Set one or more fields to zero (using the configured real type).

**Syntax**:
```
!$SER ZERO <field1> [<field2> ...] [IF <condition>]
```

**Arguments**:
- One or more positional arguments naming the fields to zero.
- Key-value pairs are **not** allowed (syntax error: "Must specify a list of
  fields").
- Optional `IF` clause.

**Generated code**:
```fortran
! file: <file> lineno: #<n>
[IF (<condition>) THEN]
<field1> = 0.0_<real_type>
<field2> = 0.0_<real_type>
...
[ENDIF]
```

Where `<real_type>` is the configured Fortran real kind parameter (default:
`ireals`, commonly overridden to `wp`).

**API calls**: None (generates inline Fortran assignments).

**Example**:
```fortran
!$SER ZERO a b c d
```

---

### 3.13 VERBATIM

**Keywords**: `VERBATIM`, `VER`

**Purpose**: Emit arbitrary Fortran code. The preprocessor strips the `!$SER
VERBATIM` prefix and outputs the remainder as literal Fortran source. This
allows embedding any Fortran statement that should only be active when
serialization is enabled (since the output is wrapped in `#ifdef` guards).

**Syntax**:
```
!$SER VERBATIM <fortran_code>
```

**Arguments**: Everything after the keyword is joined with spaces and emitted
as-is.

**Generated code**:
```fortran
<fortran_code>
```

No source annotation comment is generated for VERBATIM directives.

**API calls**: None.

**Examples**:
```fortran
!$SER VERBATIM CHARACTER (LEN=6) :: fs_realtype
!$SER VERBATIM SELECT CASE (ireals)
!$SER VERBATIM   CASE (ireals4) ; fs_realtype = 'float'
!$SER VERBATIM   CASE (ireals8) ; fs_realtype = 'double'
!$SER VERBATIM END SELECT
!$SER VERBATIM #ifdef POLLEN
```

---

### 3.14 TRACER

**Keywords**: `TRACER`, `TRA`

**Purpose**: Serialize tracer fields using a specialized tracer API. Supports
selecting tracers by name, by index/index range, or all tracers.

**Syntax**:
```
!$SER TRACER <tracerspec1> [<tracerspec2> ...] [IF <condition>]
```

**Tracer Specification Grammar**:

Each `<tracerspec>` follows this pattern:

```
<identifier>[#<stype>][@<timelevel>]
```

Where:

- **`<identifier>`** is one of:
  - A **name**: alphanumeric characters and underscores (`[a-zA-Z_0-9]+`).
  - An **index expression**: `$<expr>` or `$<expr1>-<expr2>` where each
    `<expr>` is an alphanumeric identifier optionally containing parentheses
    (e.g., `$istart`, `$istart(1)-iend(1)`).
  - The **all specifier**: `%all`.

- **`#<stype>`** (optional): The tracer storage type. Must be one of:
  - `tens`
  - `bd`
  - `surf`
  - `sedimvel`

- **`@<timelevel>`** (optional): A time level identifier (`[a-zA-Z_0-9]+`).

Full regex for tracer specification:
```
^([a-zA-Z_0-9]+|\$[a-zA-Z_0-9\(\)]+(?:-[a-zA-Z_0-9\(\)]+)?|%all)(?:#(tens|bd|surf|sedimvel))?(?:@([a-zA-Z_0-9]+))?
```

**Generated code** (per tracer spec):

For **name-based** access:
```fortran
call ppser_write_tracer_by_name('<name>', stype='<stype>', timelevel=<timelevel>)
```

For **index-based** access (single index):
```fortran
call ppser_write_tracer_by_idx(<expr>, stype='<stype>', timelevel=<timelevel>)
```

For **index-based** access (range):
```fortran
call ppser_write_tracer_by_idx(<expr1>, <expr2>, stype='<stype>', timelevel=<timelevel>)
```

For **all** tracers:
```fortran
call ppser_write_tracer_all(stype='', timelevel=<timelevel>)
```

The `stype` argument is always present (empty string if not specified). The
`timelevel` argument is only present if specified.

**API calls**: `ppser_write_tracer_by_name`, `ppser_write_tracer_by_idx`,
`ppser_write_tracer_all`

---

### 3.15 ON

**Keywords**: `ON`

**Purpose**: Enable serialization at runtime.

**Syntax**:
```
!$SER ON
```

**Arguments**: None.

**Generated code**:
```fortran
! file: <file> lineno: #<n>
call fs_enable_serialization()
```

**API call**: `fs_enable_serialization`

---

### 3.16 OFF

**Keywords**: `OFF`

**Purpose**: Disable serialization at runtime.

**Syntax**:
```
!$SER OFF
```

**Arguments**: None.

**Generated code**:
```fortran
! file: <file> lineno: #<n>
call fs_disable_serialization()
```

**API call**: `fs_disable_serialization`

---

## 4. Keyword Abbreviations Summary

| Directive        | Full Keyword(s)   | Abbreviation(s) |
|------------------|--------------------|-----------------|
| Init             | `INIT`             | `INI`           |
| Cleanup          | `CLEANUP`          | `CLE`           |
| Data             | `DATA`             | `DAT`           |
| Data (k-buffer)  | `DATA_KBUFF`       | `KBU`           |
| Data (ACC)       | `ACCDATA`          | `ACC`           |
| Mode             | `MODE`             | `MOD`           |
| Option           | `OPTION`           | `OPT`           |
| Metainfo         | `METAINFO`         | *(none)*        |
| Verbatim         | `VERBATIM`         | `VER`           |
| Register         | `REGISTER`         | `REG`           |
| RegisterTracers  | `REGISTERTRACERS`  | *(none)*        |
| Zero             | `ZERO`             | `ZER`           |
| Savepoint        | `SAVEPOINT`        | `SAV`           |
| Tracer           | `TRACER`           | `TRA`           |
| On               | `ON`               | *(none)*        |
| Off              | `OFF`              | *(none)*        |

---

## 5. Generated USE Statements

The preprocessor automatically generates Fortran `USE` statements importing
only the symbols that are actually needed. Symbols are drawn from two modules:

### 5.1 Serialization Module (configurable, default: `m_serialize`)

Imported symbols (only those actually used):

| Symbol                       | Used by Directive(s)         |
|------------------------------|------------------------------|
| `fs_write_field`             | DATA, ACCDATA                |
| `fs_read_field`              | DATA, ACCDATA                |
| `fs_write_kbuff`             | DATA_KBUFF                   |
| `fs_Option`                  | OPTION                       |
| `fs_add_serializer_metainfo` | METAINFO                     |
| `fs_register_field`          | REGISTER                     |
| `fs_RegisterAllTracers`      | REGISTERTRACERS              |
| `fs_AddFieldMetaInfo`        | *(reserved, not yet used)*   |
| `fs_create_savepoint`        | SAVEPOINT                    |
| `fs_add_savepoint_metainfo`  | SAVEPOINT                    |
| `fs_add_field_metainfo`      | *(reserved, not yet used)*   |
| `fs_enable_serialization`    | ON                           |
| `fs_disable_serialization`   | OFF                          |

### 5.2 Utility Module (`utils_ppser`)

Always imported when any serialization call is present. Imported symbols
include all `ppser_*` methods that were used, plus these always-included
utility symbols:

| Symbol                    | Description                              |
|---------------------------|------------------------------------------|
| `ppser_savepoint`         | The current savepoint variable            |
| `ppser_serializer`        | The serializer instance (for writing)     |
| `ppser_serializer_ref`    | The reference serializer (for reading)    |
| `ppser_intlength`         | Integer field length constant             |
| `ppser_reallength`        | Real field length constant                |
| `ppser_realtype`          | Real field type identifier                |
| `ppser_zrperturb`         | Perturbation value for read-perturb mode  |
| `ppser_get_mode`          | Function to query current mode            |
| `ppser_set_mode`          | MODE directive                            |
| `ppser_initialize`        | INIT directive                            |
| `ppser_finalize`          | CLEANUP directive                         |

Additional modules can be added to the `USE` statement via the `--module`
(`-m`) command-line option as a comma-separated list.

---

## 6. Preprocessor Options

These options control the behavior of the preprocessor and affect the generated
output:

| Option               | CLI Flag              | Default      | Description |
|----------------------|-----------------------|--------------|-------------|
| `ifdef`              | *(constructor only)*  | `SERIALIZE`  | C preprocessor symbol for `#ifdef`/`#endif` guards. Empty string disables guards. |
| `real`               | *(constructor only)*  | `ireals`     | Fortran real kind parameter used in ZERO directives (`0.0_<real>`). |
| `module`             | *(constructor only)*  | `m_serialize`| Name of the Fortran serialization module for `USE` statements. |
| `identical`          | `-i`                  | `True`       | When `False`, skip writing output if it is identical to existing file. |
| `acc_prefix`         | `-p` (negated)        | `True`       | Generate `#define ACC_PREFIX !$acc` at the top of output. |
| `acc_if`             | `-a`                  | `''`         | IF clause to append to OpenACC update directives. |
| `sp_as_var`          | `-s`                  | `False`      | Pass savepoint names as variable references instead of string literals. |
| `modules`            | `-m`                  | `''`         | Comma-separated list of extra modules to add to `USE` statements. |
| `verbose`            | `-v`                  | `False`      | Enable verbose output during processing. |
| `output_dir`         | `-d`                  | `''`         | Target directory for preprocessed output files. |
| `output_file`        | `-o`                  | `''`         | Explicit output file path (single file mode). |
| `recursive`          | `-r`                  | `False`      | Recursively process source directories, mirroring the tree. |

---

## 7. Error Conditions

The preprocessor reports errors and terminates for the following conditions:

| Condition | Message |
|-----------|---------|
| Unknown directive keyword | `Unknown directive encountered` |
| Multiple tokens after `IF` | `IF statement must be last argument` |
| Malformed key=value (more than one `=`) | `Problem extracting arguments and key=value pairs` |
| REGISTER with fewer than 2 positional args | `Must specify a name, a type and the field sizes` |
| REGISTER with unrecognized data type | `Data type "<type>" not understood. Valid types are: ...` |
| REGISTER with key=value pairs | `Metainformation for fields are not yet implemented` |
| OPTION with positional args | `Must specify a name and a list of key=value pairs` |
| ZERO with key=value pairs | `Must specify a list of fields` |
| SAVEPOINT with != 1 positional arg | `Must specify a name and a list of key=value pairs` |
| TRACER with invalid spec | `Tracer specification <spec> is invalid` |
| Unterminated `#ifdef` at end of file | `Unterminated #ifdef <symbol> encountered` |
| Unterminated module/program at end of file | `Unterminated module or program unit encountered` |
| Nested module/program statement | `Unexpected module/program statement` |
| Mismatched end module/program name | `Was expecting "end module/program <name>"` |
| Unexpected end module/program | `Unexpected "end module/program" statement` |
| Incorrect line continuation | `Incorrect line continuation encountered` |

---

## 8. Complete Grammar (EBNF-like)

```ebnf
(* Top-level directive *)
directive       = "!$SER" , keyword_clause ;
keyword_clause  = init_dir | cleanup_dir | savepoint_dir | data_dir
                | accdata_dir | kbuff_dir | mode_dir | option_dir
                | metainfo_dir | verbatim_dir | register_dir
                | registertracers_dir | zero_dir | tracer_dir
                | on_dir | off_dir ;

(* Common elements *)
identifier      = letter , { letter | digit | "_" } ;
letter          = "a"-"z" | "A"-"Z" ;
digit           = "0"-"9" ;
fortran_expr    = (* any valid Fortran expression, may include parens, operators, quotes *) ;
condition       = fortran_expr ;
if_clause       = "IF" , condition ;
key_value       = identifier , "=" , fortran_expr ;
positional      = fortran_expr ;    (* token without "=" *)
arg_list        = { positional | key_value } , [ if_clause ] ;

(* Individual directives *)
init_dir        = ( "INIT" | "INI" ) , { fortran_expr } , [ if_clause ] ;
cleanup_dir     = ( "CLEANUP" | "CLE" ) , { fortran_expr } ;
savepoint_dir   = ( "SAVEPOINT" | "SAV" ) , identifier , { key_value } , [ if_clause ] ;
data_dir        = ( "DATA" | "DAT" ) , { key_value } , [ if_clause ] ;
accdata_dir     = ( "ACCDATA" | "ACC" ) , { key_value } , [ if_clause ] ;
kbuff_dir       = ( "DATA_KBUFF" | "KBU" ) , "k=" , fortran_expr , "k_size=" , fortran_expr ,
                  { key_value } , [ if_clause ] ;
mode_dir        = ( "MODE" | "MOD" ) , ( mode_name | fortran_expr ) , [ if_clause ] ;
mode_name       = "write" | "read" | "read-perturb" | "CPU" | "GPU" ;
option_dir      = ( "OPTION" | "OPT" ) , key_value , { key_value } , [ if_clause ] ;
metainfo_dir    = "METAINFO" , { positional | key_value } , [ if_clause ] ;
verbatim_dir    = ( "VERBATIM" | "VER" ) , { any_token } ;
register_dir    = ( "REGISTER" | "REG" ) , identifier , type_spec ,
                  [ shortcut | dim_params ] , [ if_clause ] ;
type_spec       = "integer" | "real" | fortran_expr ;
shortcut        = "I" | "J" | "J2" | "K" | "K1" | "IJ" | "IJ3" | "IK" | "IK1"
                | "JK" | "JK1" | "IJK" | "IJK1" ;
dim_params      = { fortran_expr } ;
registertracers_dir = "REGISTERTRACERS" ;
zero_dir        = ( "ZERO" | "ZER" ) , positional , { positional } , [ if_clause ] ;
tracer_dir      = ( "TRACER" | "TRA" ) , tracer_spec , { tracer_spec } , [ if_clause ] ;
tracer_spec     = tracer_id , [ "#" , stype ] , [ "@" , timelevel ] ;
tracer_id       = identifier | "$" , index_expr , [ "-" , index_expr ] | "%all" ;
index_expr      = identifier , [ "(" , fortran_expr , ")" ] ;
stype           = "tens" | "bd" | "surf" | "sedimvel" ;
timelevel       = identifier ;
on_dir          = "ON" ;
off_dir         = "OFF" ;

(* Line continuation *)
continuation    = directive , " &" , newline ,
                  "!$SER&" , { any_token } , [ " &" , newline , continuation_tail ] ;
continuation_tail = "!$SER&" , { any_token } , [ " &" , newline , continuation_tail ] ;
```

---

## 9. Example: Full Directive Expansion

### Input

```fortran
module test
implicit none

!$SER INIT singlefile=.true.
!$SER SAVEPOINT MyStep LargeTimeStep=ntstep IF ntstep>0
!$SER DATA u=u(:,:,:,nnow)
!$SER CLEANUP

end module test
```

### Output (simplified)

```fortran
module test

#ifdef SERIALIZE
USE m_serialize, ONLY: &
  fs_write_field, &
  fs_read_field, &
  fs_create_savepoint, &
  fs_add_savepoint_metainfo
USE utils_ppser, ONLY: &
  ppser_initialize, &
  ppser_finalize, &
  ppser_savepoint, &
  ppser_serializer, &
  ppser_serializer_ref, &
  ppser_intlength, &
  ppser_reallength, &
  ppser_realtype, &
  ppser_zrperturb, &
  ppser_get_mode
#endif

implicit none

#ifdef SERIALIZE
! file: test.f90 lineno: #4
PRINT *, '>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<'
PRINT *, '>>> WARNING: SERIALIZATION IS ON <<<'
PRINT *, '>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<'

! setup serialization environment
call ppser_initialize( &
           singlefile=.true.)
! file: test.f90 lineno: #5
IF (ntstep>0) THEN
call fs_create_savepoint('MyStep', ppser_savepoint)
call fs_add_savepoint_metainfo(ppser_savepoint, 'LargeTimeStep', ntstep)
ENDIF
! file: test.f90 lineno: #6
SELECT CASE ( ppser_get_mode() )
  CASE(0)
    call fs_write_field(ppser_serializer, ppser_savepoint, 'u', u(:,:,:,nnow))
  CASE(1)
    call fs_read_field(ppser_serializer_ref, ppser_savepoint, 'u', u(:,:,:,nnow))
  CASE(2)
    call fs_read_field(ppser_serializer_ref, ppser_savepoint, 'u', u(:,:,:,nnow), ppser_zrperturb)
END SELECT
! file: test.f90 lineno: #7
! cleanup serialization environment
call ppser_finalize()
#endif

end module test
```
