"""Derive the playable R6 from the exported rig without modifying the original.

Run from any directory: python3 tools/prepare_starter_character.py
"""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
tree = ET.parse(ROOT / "rigR6.rbxmx")
rig = tree.getroot().find("Item")
assert rig is not None and rig.get("class") == "Model"


def prop(item, name):
    return item.find(f"Properties/*[@name='{name}']")


def value(item, name):
    element = prop(item, name)
    return element.text if element is not None else None


def set_value(item, tag, name, text):
    element = prop(item, name)
    if element is None:
        element = ET.SubElement(item.find("Properties"), tag, name=name)
    element.text = text


children = {value(item, "Name"): item for item in rig.findall("Item")}
body = ("HumanoidRootPart", "Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg")
for name in body:
    assert children[name].get("class") == "Part", f"Missing R6 part: {name}"
humanoid = children["Humanoid"]
assert humanoid.get("class") == "Humanoid" and value(humanoid, "RigType") == "0"
links = {
    "RootJoint": ("HumanoidRootPart", "Torso"),
    "Neck": ("Torso", "Head"),
    "Right Shoulder": ("Torso", "Right Arm"),
    "Left Shoulder": ("Torso", "Left Arm"),
    "Right Hip": ("Torso", "Right Leg"),
    "Left Hip": ("Torso", "Left Leg"),
}
for name, (part0, part1) in links.items():
    motors = [i for i in rig.iter("Item") if i.get("class") == "Motor6D" and value(i, "Name") == name]
    assert len(motors) == 1, f"Missing/duplicate Motor6D: {name}"
    motor = motors[0]
    assert value(motor, "Part0") == children[part0].get("referent"), name
    assert value(motor, "Part1") == children[part1].get("referent"), name
    assert value(motor, "Enabled") != "false", name

# Only the runtime copy loses editor data and the non-Tool reference pistol.
for name in ("AnimSaves", "Glock-17"):
    if name in children:
        rig.remove(children[name])
remaining = {i.get("referent") for i in rig.iter("Item")}
for parent in list(rig.iter("Item")):
    for item in list(parent.findall("Item")):
        if item.get("class") in ("Motor6D", "Weld", "Snap"):
            if any(value(item, p) not in remaining for p in ("Part0", "Part1")):
                assert value(item, "Name") not in links
                parent.remove(item)

set_value(rig, "string", "Name", "StarterCharacter")
set_value(rig, "Ref", "PrimaryPart", children["HumanoidRootPart"].get("referent"))
for name in body:
    set_value(children[name], "bool", "Anchored", "false")
# Preserve all dimensions, CFrames, joint C0/C1, meshes and attachments.
if humanoid.find("Item[@class='Animator']") is None:
    animator = ET.SubElement(humanoid, "Item", {"class": "Animator", "referent": "StarterCharacterAnimator"})
    ET.SubElement(animator, "Properties")
    set_value(animator, "string", "Name", "Animator")

target = ROOT / "src/StarterPlayer/StarterCharacter.rbxmx"
target.parent.mkdir(parents=True, exist_ok=True)
tree.write(target, encoding="utf-8", xml_declaration=True)
print(f"Validated R6: 7 parts, 6 body Motor6D; generated {target.relative_to(ROOT)}")
