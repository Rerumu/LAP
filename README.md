### Lua AveRage Parser

Modeled after the Lua single pass, little lookahead parsing scheme, this is an average parser.

`LARPP.lua` has the AST building, `LARPL.lua` has the stream based lexer, and `LARPO.lua` has the constructors for AST nodes.

To use, simply require `LARPP.lua` and pass a Lua source code string to `src2ast`, an AST will be returned.

The project aims to parse vanilla Lua 5.3.
