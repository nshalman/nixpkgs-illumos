# Flatten `svccfg archive` XML into sorted lines, one per leaf, each with its path of named elements, so that two
# archives can be compared regardless of the order the repository lists things in. List values keep their order.
import sys
import xml.etree.ElementTree as ET

def walk(e, path, out):
    label = e.tag + ("=" + e.get("name") if e.get("name") is not None else "")
    attrs = " ".join("%s=%s" % kv for kv in sorted(e.attrib.items()) if kv[0] != "name")
    here = path + "/" + label
    children = list(e)
    if not children:
        out.append(here + (" " + attrs if attrs else ""))
        return
    if attrs:
        out.append(here + " " + attrs)
    for i, c in enumerate(children):
        walk(c, here + ("#%d" % i if c.tag == "value_node" else ""), out)

out = []
walk(ET.parse(sys.argv[1]).getroot(), "", out)
for line in sorted(out):
    print(line)
