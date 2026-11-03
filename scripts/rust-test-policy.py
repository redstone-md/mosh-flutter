"""Lexical Rust test regions; production code outside them stays out of policy."""
import re

LEXEMES = re.compile(
    r'//[^\n]*|/\*|(?P<raw>(?:br|cr|r)(?P<hashes>\#*)")|'
    r'(?:b|c)?"(?:\\[\s\S]|[^"\\])*"|'
    r"(?:b)?'(?:\\(?:u\{[\da-fA-F_]+\}|x[\da-fA-F]{2}|.)|[^'\\\n])'"
)
DELIMITERS = re.compile(r'[()\[\]{};]')
SIGNATURE_DELIMITERS = re.compile(r'[()\[\]{};<>]')
ATTRIBUTE = re.compile(r'#\s*(?P<inner>!)?\s*\[')


def lexemes(source):
    """Yield literal/comment spans without confusing Rust lifetimes with chars."""
    cursor = 0
    while match := LEXEMES.search(source, cursor):
        start, end = match.span()
        comment = match[0].startswith(('//', '/*'))
        if match[0] == '/*':
            depth = 1
            while depth and (token := re.search(r'/\*|\*/', source[end:])):
                depth += 1 if token[0] == '/*' else -1
                end += token.end()
            if depth:
                end = len(source)
        elif match['raw']:
            delimiter = '"' + match['hashes']
            closing = source.find(delimiter, end)
            end = len(source) if closing < 0 else closing + len(delimiter)
        yield start, end, comment
        cursor = end


def mask(source):
    chunks = []
    cursor = 0
    for start, end, _ in lexemes(source):
        chunks.extend((source[cursor:start], re.sub(r'[^\n]', ' ', source[start:end])))
        cursor = end
    return ''.join(chunks) + source[cursor:]


def comments(source):
    return [(source.count('\n', 0, start) + 1, source[start:end])
            for start, end, comment in lexemes(source) if comment]


def closing_delimiter(code, start):
    stack = []
    for token in DELIMITERS.finditer(code, start):
        char = token[0]
        if char in '([{':
            stack.append(char)
        elif char in ')]}':
            if not stack or stack.pop() != {')': '(', ']': '[', '}': '{'}[char]:
                return len(code)
            if not stack:
                return token.end()
    return len(code)


def cfg_values(tokens, position=0, test_enabled=False):
    """Possible cfg values for test on/off; other flags/features stay unknown."""
    name = tokens[position]
    position += 1
    if position < len(tokens) and tokens[position] == '=':
        return {False, True}, position + 1
    if position == len(tokens) or tokens[position] != '(':
        return ({test_enabled} if name == 'test' else {False, True}), position
    children = []
    position += 1
    while position < len(tokens) and tokens[position] != ')':
        if tokens[position] == ',':
            position += 1
        else:
            values, position = cfg_values(tokens, position, test_enabled)
            children.append(values)
    position += 1
    if name == 'not' and len(children) == 1:
        return {not value for value in children[0]}, position
    if name == 'all':
        values = ({True} if all(True in child for child in children) else set())
        if any(False in child for child in children):
            values.add(False)
        return values, position
    if name == 'any':
        values = ({False} if all(False in child for child in children) else set())
        if any(True in child for child in children):
            values.add(True)
        return values, position
    return {False, True}, position


def test_attribute(attributes):
    for attribute in attributes:
        if re.fullmatch(r'\s*(?:\w+\s*::\s*)*test\s*(?:\([^)]*\))?\s*', attribute):
            return True
        cfg = re.fullmatch(r'\s*cfg\s*\((.*)\)\s*', attribute, re.S)
        if cfg:
            tokens = re.findall(r'\w+|[(),=]', cfg[1])
            if ('test' in tokens and cfg_values(tokens)[0] == {False}
                    and True in cfg_values(tokens, test_enabled=True)[0]):
                return True
    return False


def item_end(code, start):
    """Find an attributed item's body/semicolon, skipping signature delimiters."""
    cursor = start
    angles = 0
    while token := SIGNATURE_DELIMITERS.search(code, cursor):
        char = token[0]
        cursor = token.end()
        if char == '<':
            angles += 1
        elif char == '>':
            # Function-pointer/trait return arrows do not close a generic list.
            if code[token.start() - 1:token.start()] != '-':
                angles = max(0, angles - 1)
        elif char in '([' or char == '{' and angles:
            cursor = closing_delimiter(code, token.start())
        elif char == '{':
            return closing_delimiter(code, token.start())
        else:
            return token.end()
    return len(code)


def inner_end(code, start):
    stack = []
    for token in DELIMITERS.finditer(code, 0, start):
        if token[0] in '([{':
            stack.append(token.start())
        elif token[0] in ')]}' and stack:
            stack.pop()
    return closing_delimiter(code, stack[-1]) if stack else len(code)


def test_source(source):
    """Keep test-gated items and annotated tests at their original line numbers."""
    code = mask(source)
    selected = list(re.sub(r'[^\n]', ' ', source))
    # Keep local approval comments, including the line before the first attribute.
    for start, end, comment in lexemes(source):
        if comment:
            selected[start:end] = source[start:end]
    cursor = 0
    while match := ATTRIBUTE.search(code, cursor):
        start = match.start()
        inner = bool(match['inner'])
        attributes = []
        while match:
            bracket = code.index('[', match.start())
            end = closing_delimiter(code, bracket)
            attributes.append(code[bracket + 1:end - 1])
            cursor = end
            whitespace = re.match(r'\s*', code[cursor:]).end()
            match = ATTRIBUTE.match(code, cursor + whitespace)
        if test_attribute(attributes):
            end = inner_end(code, start) if inner else item_end(code, cursor)
            selected[start:end] = source[start:end]
            cursor = end
    return ''.join(selected)
