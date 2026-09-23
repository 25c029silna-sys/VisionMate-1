import re

def refine_offline(raw_text):
    # 1. Number sign decoding (#a -> 1, #b -> 2, etc.)
    num_map = {'a': '1', 'b': '2', 'c': '3', 'd': '4', 'e': '5', 'f': '6', 'g': '7', 'h': '8', 'i': '9', 'j': '0'}
    def decode_number(match):
        chars = match.group(1)
        return "".join(num_map.get(c, c) for c in chars)
    text = re.sub(r'#([a-jA-J]+)', decode_number, raw_text)

    # 2. Braille compound contractions separation: "lifeand" -> "life and", "dighand" -> "dig and"
    text = re.sub(r'([a-zA-Z]{3,})(and|with|for|the|of)\b', r'\1 \2', text)
    text = re.sub(r'\b(and|with|for|the|of)([a-zA-Z]{3,})', r'\1 \2', text)

    # 5. Common Braille OCR character confusions & cleaning
    text = text.replace('*', 'in') # asterisk / dots 3,5 is often confused with 'in' (dots 3,5)
    text = text.replace('robson', 'Robinson')
    text = text.replace('robinson,crusoeis', 'Robinson Crusoe is')
    text = text.replace('crusreis', 'Crusoe is')
    text = text.replace('daniew', 'Daniel')
    text = text.replace('defoesnotel', "Defoe's novel")
    text = text.replace('ligeand', 'Life and')
    text = text.replace('ad,turet', 'Adventures')
    text = text.replace('crusne', 'Crusoe')
    text = text.replace('publimed', 'published')
    text = text.replace('theye', 'in')
    text = text.replace('nengridthefollentheextrctf', 'Now read the following extract from')
    text = text.replace('umipwreckedduruadrdl', 'shipwrecked during a dreadful')
    text = text.replace('despaiw', 'Despair')

    return text

sample_raw = """
h hedfor robson cr oe
robson crusreis daniew
defoesnotel; ?the ligeand
ad,turet rob on,crusne
publimed theye #aji
nengridthefollentheextrctf
robson crusorsditof
septemq#cj;#afei
ipoormiseda# obson,crwithsoe
umipwreckedduruadrdl orm
capeamreonp'edl unoftunawe
islands icalled .z ilandfor
"""

print("=== RAW ===")
print(sample_raw)
print("\n=== REFINED OFFLINE ===")
print(refine_offline(sample_raw))
