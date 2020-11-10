### Lua Average Parser

Modeled after the Lua single pass, little lookahead parsing scheme, this is an average parser.

`parser.lua` has the AST building, `lexer.lua` has the stream based lexer, and `node.lua` has the constructors for AST nodes.

Invoke `main.lua` by `lua main.lua --help` for options.

The project aims to parse vanilla Lua 5.3.
