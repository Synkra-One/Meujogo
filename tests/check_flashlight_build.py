"""Check the built Rojo tree, including inactive imported model templates."""
import collections
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
expected = {
    "FlashlightController", "FlashlightSystem", "FlashlightHUD", "FlashlightPose",
    "FlashlightVisuals", "FlashlightExposureFX", "FlashlightRules", "FlashlightConfig",
    "FlashlightTargeting", "FlashlightRig",
}
counts = collections.Counter()
remotes = []


def walk(parent, path=""):
    for item in parent.findall("Item"):
        name = item.findtext('./Properties/string[@name="Name"]')
        child_path = path + "/" + (name or "?")
        if name in expected:
            counts[name] += 1
        if name == "Flashlight" and item.attrib["class"] == "RemoteEvent":
            remotes.append(child_path)
        walk(item, child_path)


walk(root)
assert all(counts[name] == 1 for name in expected), counts
assert remotes == ["/ReplicatedStorage/Remotes/Flashlight"], remotes
print("PASS: one flashlight controller, one server system, one of each module and one shared RemoteEvent in built place")
