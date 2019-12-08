### Lua AveRage Parser

Modeled after the Lua single pass, little lookahead parsing scheme, this is an average parser.

`LARPP.lua` has the AST building, `LARPL.lua` has the stream based lexer, and `LARPO.lua` has the constructors for AST nodes.

To use, simply require `LARPP.lua` and pass a Lua source code string to `src2ast`, an AST will be returned.

This parser has some changes from regular Lua, and although it aims to parse vanilla Lua 5.3 you should be aware of the following change(s):

`repeat until` blocks no longer share a scope with the condition.
