import re

def merge_spaced_letters(text):
    # Regex that finds sequences of single letters separated by a single space:
    # e.g., "p a a" -> "paa", "c k a m a" -> "ckama", "r o b i n s o n" -> "robinson"
    # But preserve standalone 'a' or 'I' when surrounded by multi-letter words: "is a book" -> "is a book"
    def replacer(match):
        segment = match.group(0)
        # If the segment is just "word a word", don't merge
        letters = segment.split(' ')
        # If it's just 'a' or 'I' alone, return as is
        if len(letters) == 1:
            return segment
        # If it's a sequence of single letters (e.g. ['p', 'a', 'a'] or ['c', 'k', 'a', 'm', 'a'])
        # merge them into a single word
        return "".join(letters)

    # Match 2 or more single letters separated by exactly one space:
    pattern = r'\b[a-zA-Z](?: [a-zA-Z])+\b'
    
    # We only apply this if the line/clause is heavily fragmented (has multiple single letters)
    # Let's test on samples
    return re.sub(pattern, replacer, text)

samples = [
    "p a a",
    "g k a b c",
    "c k a m a",
    "x l a",
    "c c c",
    "a k",
    "k c a",
    "l a ed",
    "r o b i n s o n  c r u s o e",
    "this is a good test of a system",
]

for s in samples:
    print(f"'{s}' -> '{merge_spaced_letters(s)}'")
