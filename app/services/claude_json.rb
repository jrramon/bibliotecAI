# Pulls the JSON object out of a `claude -p` assistant response.
#
# Claude is asked for "a SINGLE JSON object, no prose" but doesn't always
# comply: it may wrap the object in a ```json fence, prepend a preamble
# ("I was unable to crop the image..."), or append an epilogue ("This image
# is not a book cover..."). All three have shown up in production.
#
# We take the substring from the first "{" to the last "}", so JSON.parse
# sees only the object regardless of surrounding chatter. Best-effort: if
# the surrounding prose itself contains stray braces the slice can be wrong,
# but the caller still rescues JSON::ParserError and surfaces the raw output.
module ClaudeJson
  module_function

  def extract(text)
    str = text.to_s
    open = str.index("{")
    close = str.rindex("}")
    return str if open.nil? || close.nil? || close < open
    str[open..close]
  end
end
