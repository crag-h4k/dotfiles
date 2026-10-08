# home/dot_local/share/dotfiles/openviking/readonly_opencode_config.py
"""Insert one MCP server while preserving unrelated JSONC text."""
import json
import re

TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/|\s+|.', re.S)


def tokens(text):
    return [token for token in TOKEN.finditer(text)
            if not token.group().isspace() and not token.group().startswith(("//", "/*"))]


def decode(text):
    cleaned = list(text)
    for token in TOKEN.finditer(text):
        if token.group().startswith(("//", "/*")):
            cleaned[token.start():token.end()] = ["\n" if char == "\n" else " " for char in token.group()]
    significant = tokens(text)
    for previous, token, following in zip(significant, significant[1:], significant[2:]):
        if token.group() == "," and following.group() in ("}", "]") and previous.group() not in ("{", "[", ",", ":"):
            cleaned[token.start()] = " "

    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError("duplicate OpenCode config key")
            value[key] = item
        return value

    return json.loads("".join(cleaned), object_pairs_hook=unique)


def object_members(text):
    significant = tokens(text)
    if not significant or significant[0].group() != "{":
        raise ValueError("OpenCode config member is not an object")
    members = {}
    index = 1
    while index < len(significant) and significant[index].group() != "}":
        key = json.loads(significant[index].group())
        index += 1
        if significant[index].group() != ":":
            raise ValueError("invalid OpenCode config object")
        index += 1
        start = significant[index].start()
        depth = 0
        while index < len(significant):
            value = significant[index].group()
            if depth == 0 and value in (",", "}"):
                break
            if value in ("{", "["):
                depth += 1
            elif value in ("}", "]"):
                depth -= 1
            end = significant[index].end()
            index += 1
        members[key] = (start, end)
        if significant[index].group() == ",":
            index += 1
    return members, significant[0].end()


def insert(text, path, value):
    members, opening = object_members(text)
    key = path[0]
    if key in members:
        start, end = members[key]
        if len(path) == 1:
            if decode(text[start:end]) != value:
                raise ValueError("existing OpenViking MCP entry differs; review it before replacing")
            return text
        child = insert(text[start:end], path[1:], value)
        return text[:start] + child + text[end:]
    nested = value
    for child in reversed(path[1:]):
        nested = {child: nested}
    member = json.dumps(key) + ": " + json.dumps(nested, indent=2)
    comma = "," if members else ""
    return text[:opening] + "\n" + member + comma + text[opening:]


def merge(text, server):
    if not text.strip():
        text = "{}\n"
    if not isinstance(decode(text), dict):
        raise ValueError("OpenCode config is not an object")
    updated = insert(text, ("mcp", "servers", "openviking"), server)
    decode(updated)
    return updated
