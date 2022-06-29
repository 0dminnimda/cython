from pegen.tokenizer import Tokenizer

from .Parser import CythonParser
from .TokenStream import TokenStreamer


def parse(f, context, source_desc, scope, pxd, full_module_name):
    token_stream = TokenStreamer(f, source_desc, source_encoding=f.encoding,
                                 scope=scope, context=context)
    verbose = context.options.verbose
    tokenizer = Tokenizer(iter(token_stream), verbose=verbose)  # , path=path)
    parser = CythonParser(
        tokenizer,
        source_desc,
        verbose=verbose,
        filename=full_module_name,
        py_version=None,
    )
    return parser.parse("file")
