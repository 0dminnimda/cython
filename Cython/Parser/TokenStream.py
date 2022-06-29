import token
from tokenize import TokenInfo

from ..Compiler.Scanning import PyrexScanner


SYMBOL_TO_TOKEN = {
    "EOF": token.ENDMARKER,
    "IDENT": token.NAME,
    "INT": token.NUMBER,
    "FLOAT": token.NUMBER,
    "IMAG": token.NUMBER,
    # token.STRING is handled in the __iter__
    # token.NEWLINE is handled in the __iter__
    "INDENT": token.INDENT,
    "DEDENT": token.DEDENT,
    # token.OP is handled in the __iter__
    # token.AWAIT is handled in the __iter__
    # token.ASYNC is handled in the __iter__
    # cython don't use token.TYPE_IGNORE
    # cython don't use token.TYPE_COMMENT
    # token.SOFT_KEYWORD is useless, at least for now
    # cython will generate it's our errors, so no token.ERRORTOKEN
    # cython don't separate commentline from it's newline,
    # but it's always token.NL, so it doesn't matter
    "commentline": token.COMMENT,
    # some symbols for token.NL are ignored, hopefully token.NL can be ignored
    # cython don't use token.ENCODING
    # token.N_TOKENS should not be an output of the tokenizer
    # token.NT_OFFSET should not be an output of the tokenizer
}


class TokenStreamer(PyrexScanner):
    line_string = ""
    token_start = 0, 0

    def read_the_stream(self, size):
        self.line_string = self.stream.readline()
        return self.line_string

    def pair_generator(self):
        while 1:
            symbol = self.next()
            yield symbol, self.systring
            if symbol == "EOF":
                break

    def update_taken_start(self):
        self.token_start = self.start_line, self.start_col
        return self.token_start

    def create_token(self, type, string):
        if type == token.NEWLINE:
            end = self.token_start[0], self.token_start[1] + len(string)
        else:
            end = self.cur_line, self.cur_pos - self.cur_line_start
        return TokenInfo(type, string, self.token_start, end, self.line_string)

    def __iter__(self):
        string = ""
        for symbol, symbol_string in self.pair_generator():
            if symbol == "BEGIN_STRING":
                self.update_taken_start()
                string += symbol_string
                continue

            if symbol == "END_STRING":
                yield self.create_token(token.STRING, string + symbol_string)
                string = ""
                continue

            if string:
                assert symbol in ("CHARS", "NEWLINE", "ESCAPE"), symbol
                string += symbol_string
                continue

            if symbol == "NEWLINE":
                assert symbol_string == "", symbol_string
                self.update_taken_start()
                yield self.create_token(token.NEWLINE, "\n")
                continue

            if symbol in token.EXACT_TOKEN_TYPES:
                self.update_taken_start()
                yield self.create_token(token.OP, symbol_string)
                continue

            self.update_taken_start()
            yield self.create_token(SYMBOL_TO_TOKEN[symbol], symbol_string)
