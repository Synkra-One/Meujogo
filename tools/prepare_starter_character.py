"""Maintain separate edit-mode R6 references and the playable character.

Run from any directory: python3 tools/prepare_starter_character.py
Repair the normal reference if needed: python3 tools/prepare_starter_character.py --scale-reference 1
"""
from pathlib import Path
import copy
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MONSTER_REFERENCE_SCALE = 1.2
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


def scale_vector(element, factor, center=(0.0, 0.0, 0.0)):
    """Scale an XML Vector3/CFrame translation, preserving its rotation."""
    if element is None:
        return
    for axis, origin in zip(("X", "Y", "Z"), center):
        coordinate = element.find(axis)
        if coordinate is not None:
            source = float(coordinate.text)
            if origin == 0 and source == 0:
                continue  # Preserve harmless signed zero from the Studio export.
            coordinate.text = format(origin + (source - origin) * factor, ".9g")


def scale_r6_body(model, target_scale):
    """Equivalent geometric subset of Model:ScaleTo for this known R6 body.

    Editor-only AnimSaves and the reference pistol are intentionally excluded:
    animation keyframes stay canonical and the weapon has its own rig.
    """
    model_children = {value(item, "Name"): item for item in model.findall("Item")}
    model_humanoid = model_children["Humanoid"]
    current_scale = float(value(model, "ScaleFactor") or 1)
    if abs(current_scale - target_scale) < 1e-9:
        return
    factor = target_scale / current_scale

    def body_bottom():
        lowest = float("inf")
        for part_name in body:
            part = model_children[part_name]
            size = prop(part, "size")
            frame = prop(part, "CFrame")
            sx, sy, sz = (float(size.find(axis).text) for axis in ("X", "Y", "Z"))
            # World-space vertical half-extent of an oriented box.
            half_y = (
                abs(float(frame.find("R10").text)) * sx
                + abs(float(frame.find("R11").text)) * sy
                + abs(float(frame.find("R12").text)) * sz
            ) * 0.5
            lowest = min(lowest, float(frame.find("Y").text) - half_y)
        return lowest

    original_bottom = body_bottom()

    world_pivot = prop(model, "WorldPivotData")
    pivot_cframe = world_pivot.find("CFrame") if world_pivot is not None else None
    if pivot_cframe is None:
        pivot_cframe = prop(model_children["HumanoidRootPart"], "CFrame")
    pivot = tuple(float(pivot_cframe.find(axis).text) for axis in ("X", "Y", "Z"))

    for name in body:
        part = model_children[name]
        # BasePart serializes this legacy property as lowercase "size".
        scale_vector(prop(part, "size"), factor)
        scale_vector(prop(part, "CFrame"), factor, pivot)
        scale_vector(prop(part, "PivotOffset"), factor)

        for descendant in part.iter("Item"):
            if descendant is part:
                continue
            class_name = descendant.get("class")
            descendant_name = value(descendant, "Name")
            if class_name == "Attachment":
                scale_vector(prop(descendant, "CFrame"), factor)
            elif class_name == "Motor6D" and descendant_name in links:
                scale_vector(prop(descendant, "C0"), factor)
                scale_vector(prop(descendant, "C1"), factor)

    hip_height = prop(model_humanoid, "HipHeight")
    if hip_height is not None:
        hip_height.text = format(float(hip_height.text) * factor, ".9g")

    # ScaleTo uses the HumanoidRootPart pivot. Without this correction, a
    # larger reference rig sinks its longer legs into the floor and can look
    # almost the same height as the normal R6. Preserve the authored foot
    # plane by translating the complete body after scaling.
    floor_correction = original_bottom - body_bottom()
    if abs(floor_correction) > 1e-9:
        for name in body:
            frame_y = prop(model_children[name], "CFrame").find("Y")
            frame_y.text = format(float(frame_y.text) + floor_correction, ".9g")
        if pivot_cframe is not None:
            pivot_y = pivot_cframe.find("Y")
            pivot_y.text = format(float(pivot_y.text) + floor_correction, ".9g")

    set_value(model, "float", "ScaleFactor", format(target_scale, ".9g"))


def translate_r6_body(model, offset):
    model_children = {value(item, "Name"): item for item in model.findall("Item")}
    for name in body:
        frame = prop(model_children[name], "CFrame")
        for axis, delta in zip(("X", "Y", "Z"), offset):
            coordinate = frame.find(axis)
            coordinate.text = format(float(coordinate.text) + delta, ".9g")

    world_pivot = prop(model, "WorldPivotData")
    pivot_cframe = world_pivot.find("CFrame") if world_pivot is not None else None
    if pivot_cframe is not None:
        for axis, delta in zip(("X", "Y", "Z"), offset):
            coordinate = pivot_cframe.find(axis)
            coordinate.text = format(float(coordinate.text) + delta, ".9g")


def root_position(model):
    model_children = {value(item, "Name"): item for item in model.findall("Item")}
    frame = prop(model_children["HumanoidRootPart"], "CFrame")
    return tuple(float(frame.find(axis).text) for axis in ("X", "Y", "Z"))


if len(sys.argv) == 3 and sys.argv[1] == "--scale-reference":
    scale_r6_body(rig, float(sys.argv[2]))
    # Preserve the Studio export's serialization style. In particular, avoid
    # rewriting thousands of explicit empty tags inside AnimSaves.
    tree.getroot().set("xmlns:xmime", "http://www.w3.org/2005/05/xmlmime")
    tree.write(ROOT / "rigR6.rbxmx", encoding="unicode", xml_declaration=False, short_empty_elements=False)
    print(f"Animation R6 scaled to {sys.argv[2]}x: rigR6.rbxmx")
    raise SystemExit(0)

# R6 novo and the shared playable template stay at scale 1. AppearanceManager
# applies the monster scale only after RoleAssignment identifies the Monster.
# Emit a separate Workspace reference already scaled for monster animation.
animation_target = ROOT / "src/Workspace/R6Monster.rbxmx"
existing_reference_position = None
if animation_target.exists():
    existing_tree = ET.parse(animation_target)
    existing_reference = existing_tree.getroot().find("Item")
    if existing_reference is not None:
        existing_reference_position = root_position(existing_reference)

animation_tree = copy.deepcopy(tree)
animation_rig = animation_tree.getroot().find("Item")
assert animation_rig is not None
scale_r6_body(animation_rig, MONSTER_REFERENCE_SCALE)
animation_children = {value(item, "Name"): item for item in animation_rig.findall("Item")}
for name in ("AnimSaves", "Glock-17"):
    if name in animation_children:
        animation_rig.remove(animation_children[name])
animation_remaining = {item.get("referent") for item in animation_rig.iter("Item")}
for parent in list(animation_rig.iter("Item")):
    for item in list(parent.findall("Item")):
        if item.get("class") in ("Motor6D", "Weld", "Snap"):
            if any(value(item, endpoint) not in animation_remaining for endpoint in ("Part0", "Part1")):
                assert value(item, "Name") not in links
                parent.remove(item)
set_value(animation_rig, "string", "Name", "R6 Monster")
animation_body = {value(item, "Name"): item for item in animation_rig.findall("Item")}
set_value(animation_rig, "Ref", "PrimaryPart", animation_body["HumanoidRootPart"].get("referent"))
for name in body:
    set_value(animation_body[name], "bool", "Anchored", "true" if name == "HumanoidRootPart" else "false")

# Preserve a manually chosen edit-mode position. On first generation, put the
# reference beside the exported R6 instead of exactly on top of it.
current_reference_position = root_position(animation_rig)
if existing_reference_position is not None:
    offset = tuple(target - current for target, current in zip(existing_reference_position, current_reference_position))
else:
    offset = (4.0, 0.0, 0.0)
translate_r6_body(animation_rig, offset)

animation_target.parent.mkdir(parents=True, exist_ok=True)
animation_tree.write(animation_target, encoding="utf-8", xml_declaration=True)

scale_r6_body(rig, 1.0)

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
print(f"Generated {MONSTER_REFERENCE_SCALE:g}x animation reference: {animation_target.relative_to(ROOT)}")
