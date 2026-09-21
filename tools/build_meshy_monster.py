#!/usr/bin/env python3
"""
Gera o rig R6 de teste "R6 Monster Meshy" a partir do FBX do Meshy em model/.

O FBX do Meshy e UMA malha estatica, fechada, sem esqueleto e sem skin. Ela ja
tem silhueta de R6 (cabeca, torso, 2 bracos, 2 pernas encostados, separados
por vincos). Este script NAO deforma nada: corta a malha ao longo dos vincos em
6 pecas rigidas, tampa cada abertura, e monta o R6 com Motor6D nos mesmos eixos
do R6 padrao (RootJoint/Neck/Shoulders/Hips), para as animacoes R6 existentes
funcionarem.

Saidas (nada existente e alterado ou apagado):
  model/roblox_upload/parts/*.obj      6 malhas para importar no Studio
  model/roblox_upload/textures/*.png   mapas PBR (2048px) para SurfaceAppearance
  model/roblox_upload/asset_ids.json   colar aqui os ids depois do upload
  src/Workspace/R6MonsterMeshy.rbxmx   rig R6 (Rojo: Workspace["R6 Monster Meshy"])
  src/ServerStorage/MonsterMeshyVisuals.rbxmx
                                       so as 6 MeshParts (MeshId/TextureID/SurfaceAppearance)
                                       que server/MonsterMeshyVisuals.lua veste no monstro atual

Uso:
  python3 tools/build_meshy_monster.py

Rode de novo depois de preencher asset_ids.json para gravar os ids no rig.
"""

import collections
import json
import math
import re
import struct
import sys
import uuid
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FBX_PATH = ROOT / "model/Meshy_AI_Charred_Hollow_Figure_0918193209_texture.fbx"
TEXTURE_SOURCES = {
    "ColorMap": ROOT / "model/Meshy_AI_Charred_Hollow_Figure_0918193209_texture.png",
    "NormalMap": ROOT / "model/Meshy_AI_Charred_Hollow_Figure_0918193209_texture_normal.png",
    "MetalnessMap": ROOT / "model/Meshy_AI_Charred_Hollow_Figure_0918193209_texture_metallic.png",
    "RoughnessMap": ROOT / "model/Meshy_AI_Charred_Hollow_Figure_0918193209_texture_roughness.png",
}
OUT_DIR = ROOT / "model/roblox_upload"
RIG_PATH = ROOT / "src/Workspace/R6MonsterMeshy.rbxmx"
VISUALS_PATH = ROOT / "src/ServerStorage/MonsterMeshyVisuals.rbxmx"
MAP_NAMES = ("ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap")
ANIM_CONFIG = ROOT / "src/ReplicatedStorage/Modules/MonsterAnimationConfig.lua"

# --- Segmentacao (coordenadas originais do FBX; personagem olha para +Z) -----
# Planos medidos nos vincos reais da malha (aneis de vertices em Y=0.56/-0.10,
# X=+-0.368). Ver docs/MonstroMeshy.md.
HEAD_MIN_Y = 0.566  # cabeca/torso
ARM_MIN_X = 0.368  # braco/torso (|x| a partir daqui)
ARM_BOTTOM_Y = -0.19  # abaixo disso so existem as pernas
LEG_TOP_Y = -0.104  # torso/pernas
JAW_MIN_Y, JAW_MIN_Z, JAW_MAX_X = 0.45, 0.153, 0.2  # dentes da boca pendurados no peito

# Escala uniforme: metade da largura do torso (0.368) = 1 stud, igual ao R6 (torso 2 studs).
SCALE = 1.0 / ARM_MIN_X

PART_NAMES = ["Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"]
FILE_NAMES = {
    "Head": "Head", "Torso": "Torso", "Left Arm": "LeftArm", "Right Arm": "RightArm",
    "Left Leg": "LeftLeg", "Right Leg": "RightLeg",
}
# Tamanho de cada peca no R6 padrao, para escalar os Attachments.
STD_SIZE = {
    "Head": (2, 1, 1), "Torso": (2, 2, 1), "Left Arm": (1, 2, 1), "Right Arm": (1, 2, 1),
    "Left Leg": (1, 2, 1), "Right Leg": (1, 2, 1), "HumanoidRootPart": (2, 2, 1),
}
ATTACHMENTS = {  # posicoes do R6 padrao (as mesmas de src/Workspace/R6Monster.rbxmx / 1.2)
    "Head": {"HatAttachment": (0, 0.6, 0), "FaceFrontAttachment": (0, 0, -0.6),
             "FaceCenterAttachment": (0, 0, 0), "HairAttachment": (0, 0.6, 0)},
    "Torso": {"BodyBackAttachment": (0, 0, 0.5), "WaistFrontAttachment": (0, -1, -0.5),
              "BodyFrontAttachment": (0, 0, -0.5), "LeftCollarAttachment": (-1, 1, 0),
              "RightCollarAttachment": (1, 1, 0), "WaistCenterAttachment": (0, -1, 0),
              "NeckAttachment": (0, 1, 0), "WaistBackAttachment": (0, -1, 0.5)},
    "Left Arm": {"LeftShoulderAttachment": (0, 1, 0), "LeftGripAttachment": (0, -1, 0)},
    "Right Arm": {"RightShoulderAttachment": (0, 1, 0), "RightGripAttachment": (0, -1, 0)},
    "Left Leg": {"LeftFootAttachment": (0, -1, 0)},
    "Right Leg": {"RightFootAttachment": (0, -1, 0)},
    "HumanoidRootPart": {"RootAttachment": (0, 0, 0)},
}
# Matrizes de eixo do R6 padrao (R00..R22). Sao elas que fazem as animacoes R6 servirem.
ROT_ROOT = (-1, 0, 0, 0, 0, 1, 0, 1, 0)  # RootJoint e Neck
ROT_R = (0, 0, 1, 0, 1, 0, -1, 0, 0)  # Right Shoulder / Right Hip
ROT_L = (0, 0, -1, 0, 1, 0, 1, 0, 0)  # Left Shoulder / Left Hip

# Posicao do rig de teste: ao lado do "R6 Monster" (x=5), pes no mesmo chao (y=10).
RIG_ORIGIN_X, RIG_GROUND_Y, RIG_ORIGIN_Z = 15.0, 10.0, -388.5
TEXTURE_PX = 2048


# =============================================================================
# Leitura do FBX binario
# =============================================================================
def _read_node(d, pos, ver):
    if ver >= 7500:
        end, nprops, _plen = struct.unpack_from("<QQQ", d, pos)
        pos += 24
    else:
        end, nprops, _plen = struct.unpack_from("<III", d, pos)
        pos += 12
    nlen = d[pos]
    pos += 1
    if end == 0:
        return None, pos
    name = d[pos:pos + nlen].decode("latin1")
    pos += nlen
    props = []
    for _ in range(nprops):
        t = chr(d[pos])
        pos += 1
        if t == "Y":
            props.append(struct.unpack_from("<h", d, pos)[0]); pos += 2
        elif t == "C":
            props.append(bool(d[pos])); pos += 1
        elif t == "I":
            props.append(struct.unpack_from("<i", d, pos)[0]); pos += 4
        elif t == "F":
            props.append(struct.unpack_from("<f", d, pos)[0]); pos += 4
        elif t == "D":
            props.append(struct.unpack_from("<d", d, pos)[0]); pos += 8
        elif t == "L":
            props.append(struct.unpack_from("<q", d, pos)[0]); pos += 8
        elif t in "fdlib":
            n, enc, clen = struct.unpack_from("<III", d, pos)
            pos += 12
            raw = d[pos:pos + clen]
            pos += clen
            if enc == 1:
                raw = zlib.decompress(raw)
            code = {"f": "f", "d": "d", "l": "q", "i": "i", "b": "b"}[t]
            props.append(list(struct.unpack("<%d%s" % (n, code), raw)))
        elif t in "SR":
            n = struct.unpack_from("<I", d, pos)[0]
            pos += 4
            raw = d[pos:pos + n]
            pos += n
            props.append(raw.decode("latin1") if t == "S" else raw)
        else:
            raise ValueError("tipo de propriedade FBX desconhecido: " + t)
    children = []
    while pos < end:
        child, pos = _read_node(d, pos, ver)
        if child is None:
            break
        children.append(child)
    return (name, props, children), end


def read_fbx_mesh(path):
    """Devolve dict com verts, quads, loops, uvs, uv_index, normals, normal_index e contagens."""
    d = path.read_bytes()
    if not d.startswith(b"Kaydara FBX Binary"):
        raise SystemExit("FBX precisa ser binario: " + str(path))
    ver = struct.unpack_from("<I", d, 23)[0]
    pos, top = 27, []
    while pos < len(d) - 40:
        node, pos = _read_node(d, pos, ver)
        if node is None:
            break
        top.append(node)
    objects = next(n for n in top if n[0] == "Objects")[2]
    census = collections.Counter(n[0] for n in objects)
    geos = [n for n in objects if n[0] == "Geometry"]
    if len(geos) != 1:
        raise SystemExit("Esperava 1 Geometry no FBX, achei %d" % len(geos))
    g = {c[0]: c for c in geos[0][2]}

    def data(layer, key):
        sub = {c[0]: c for c in g[layer][2]}
        return sub[key][1][0] if key in sub else None

    flat = g["Vertices"][1][0]
    verts = [tuple(flat[i:i + 3]) for i in range(0, len(flat), 3)]
    polys, loops, cur, curl = [], [], [], []
    for loop, idx in enumerate(g["PolygonVertexIndex"][1][0]):
        cur.append(~idx if idx < 0 else idx)
        curl.append(loop)
        if idx < 0:
            polys.append(cur); loops.append(curl); cur, curl = [], []
    uv = data("LayerElementUV", "UV")
    nr = data("LayerElementNormal", "Normals")
    nri = data("LayerElementNormal", "NormalsIndex")
    uvi = data("LayerElementUV", "UVIndex")
    if nri is None or uvi is None:
        raise SystemExit("FBX sem indices de UV/normal (esperado IndexToDirect).")
    if any(len(p) != 4 for p in polys):
        raise SystemExit("FBX tem poligonos que nao sao quads; ajuste o script.")
    return {
        "verts": verts, "quads": polys, "loops": loops,
        "uvs": [tuple(uv[i:i + 2]) for i in range(0, len(uv), 2)], "uv_index": uvi,
        "normals": [tuple(nr[i:i + 3]) for i in range(0, len(nr), 3)], "normal_index": nri,
        "census": census,
        "has_skin": any(n[0] == "Deformer" for n in objects),
    }


# =============================================================================
# Segmentacao e tampas
# =============================================================================
def classify(mesh):
    """Rotulo de cada quad. No FBX o personagem olha para +Z, entao +X e o lado ESQUERDO dele."""
    verts, labels = mesh["verts"], []
    for quad in mesh["quads"]:
        cx = sum(verts[i][0] for i in quad) / 4
        cy = sum(verts[i][1] for i in quad) / 4
        cz = sum(verts[i][2] for i in quad) / 4
        if cy >= HEAD_MIN_Y or (cy > JAW_MIN_Y and cz > JAW_MIN_Z and abs(cx) < JAW_MAX_X):
            labels.append("Head")
        elif abs(cx) >= ARM_MIN_X and cy >= ARM_BOTTOM_Y:
            labels.append("Left Arm" if cx > 0 else "Right Arm")
        elif cy < LEG_TOP_Y and (abs(cx) < ARM_MIN_X or cy < ARM_BOTTOM_Y):
            labels.append("Left Leg" if cx > 0 else "Right Leg")
        else:
            labels.append("Torso")
    return labels


def _to_rig_space(p):
    """FBX (olha +Z) -> Roblox (olha -Z): gira 180 graus em Y e aplica a escala uniforme."""
    return (-p[0] * SCALE, p[1] * SCALE, -p[2] * SCALE)


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _unit(v):
    m = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)
    return (v[0] / m, v[1] / m, v[2] / m) if m > 1e-12 else (0.0, 1.0, 0.0)


def build_part(mesh, quad_ids):
    """Peca independente: posicoes/UV/normais compactos, triangulos e tampas nas aberturas."""
    pos_map, positions = {}, []
    uv_map, uvs = {}, []
    nrm_map, normals = {}, []
    tris = []

    def pid(v):
        if v not in pos_map:
            pos_map[v] = len(positions)
            positions.append(_to_rig_space(mesh["verts"][v]))
        return pos_map[v]

    def uid(u):
        if u not in uv_map:
            uv_map[u] = len(uvs)
            uvs.append(mesh["uvs"][u])
        return uv_map[u]

    def nid(n):
        if n not in nrm_map:
            nrm_map[n] = len(normals)
            x, y, z = mesh["normals"][n]
            normals.append((-x, y, -z))
        return nrm_map[n]

    edge_count = collections.Counter()
    directed = []  # (a, b, uv_a) por aresta de cada quad
    for qi in quad_ids:
        quad, loops = mesh["quads"][qi], mesh["loops"][qi]
        corners = [(pid(quad[k]), uid(mesh["uv_index"][loops[k]]), nid(mesh["normal_index"][loops[k]]))
                   for k in range(4)]
        tris.append((corners[0], corners[1], corners[2]))
        tris.append((corners[0], corners[2], corners[3]))
        for k in range(4):
            a, b = corners[k][0], corners[(k + 1) % 4][0]
            edge_count[(min(a, b), max(a, b))] += 1
            directed.append((a, b, corners[k][1]))

    # Arestas de borda -> lacos fechados -> tampa em leque (b, a, centro): mesma orientacao da casca.
    boundary = {a: (b, uva) for a, b, uva in directed if edge_count[(min(a, b), max(a, b))] == 1}
    seen, caps = set(), 0
    for start in list(boundary):
        if start in seen:
            continue
        loop, v = [], start
        while v in boundary and v not in seen:
            seen.add(v)
            loop.append(v)
            v = boundary[v][0]
        if len(loop) < 3:
            continue
        centre = tuple(sum(positions[i][k] for i in loop) / len(loop) for k in range(3))
        ci = len(positions)
        positions.append(centre)
        cap_uv = boundary[loop[0]][1]
        for a in loop:
            b = boundary[a][0]
            n = _unit(_cross(_sub(positions[a], positions[b]), _sub(centre, positions[b])))
            ni = len(normals)
            normals.append(n)
            tris.append(((b, cap_uv, ni), (a, cap_uv, ni), (ci, cap_uv, ni)))
        caps += 1

    # Malha final precisa ser fechada (cada aresta em exatamente 2 triangulos).
    final = collections.Counter()
    for tri in tris:
        for k in range(3):
            a, b = tri[k][0], tri[(k + 1) % 3][0]
            final[(a, b)] += 1
    open_edges = sum(1 for (a, b), c in final.items() if final.get((b, a), 0) != c)
    xs, ys, zs = zip(*positions)
    return {
        "positions": positions, "uvs": uvs, "normals": normals, "tris": tris, "caps": caps,
        "open_edges": open_edges, "quads": len(quad_ids),
        "min": (min(xs), min(ys), min(zs)), "max": (max(xs), max(ys), max(zs)),
    }


def write_obj(path, name, part):
    lo, hi = part["min"], part["max"]
    c = tuple((lo[k] + hi[k]) / 2 for k in range(3))  # centrado no bbox: e assim que o MeshPart o posiciona
    lines = ["# Gerado por tools/build_meshy_monster.py (unidade = stud, olha para -Z, centrado no bbox)",
             "o " + name]
    lines += ["v %.6f %.6f %.6f" % (p[0] - c[0], p[1] - c[1], p[2] - c[2]) for p in part["positions"]]
    lines += ["vt %.6f %.6f" % uv for uv in part["uvs"]]
    lines += ["vn %.6f %.6f %.6f" % n for n in part["normals"]]
    for tri in part["tris"]:
        lines.append("f " + " ".join("%d/%d/%d" % (v + 1, t + 1, n + 1) for v, t, n in tri))
    path.write_text("\n".join(lines) + "\n")


# =============================================================================
# Rig R6
# =============================================================================
def compute_rig(parts):
    """Tudo em espaco do rig (studs, pes/torso alinhados ao mundo depois do offset)."""
    box = {}
    for name, part in parts.items():
        lo, hi = part["min"], part["max"]
        box[name] = {"center": tuple((lo[k] + hi[k]) / 2 for k in range(3)),
                     "size": tuple(hi[k] - lo[k] for k in range(3)), "lo": lo, "hi": hi}
    torso, head = box["Torso"], box["Head"]
    feet_y = min(box["Left Leg"]["lo"][1], box["Right Leg"]["lo"][1])
    ox = RIG_ORIGIN_X - torso["center"][0]
    oy = RIG_GROUND_Y - feet_y
    oz = RIG_ORIGIN_Z - torso["center"][2]
    off = (ox, oy, oz)

    def world(p):
        return (p[0] + ox, p[1] + oy, p[2] + oz)

    cframes = {n: world(b["center"]) for n, b in box.items()}
    cframes["HumanoidRootPart"] = cframes["Torso"]
    sizes = {n: b["size"] for n, b in box.items()}
    sizes["HumanoidRootPart"] = box["Torso"]["size"]

    # Pontos de junta (mundo). Mesma logica do R6: pescoco na base da cabeca, ombro na borda
    # interna do braco a 1/4 da altura abaixo do topo, quadril na borda externa do topo da perna.
    joint = {"Neck": world((head["center"][0], HEAD_MIN_Y * SCALE, head["center"][2]))}
    for side, sign in (("Right", 1), ("Left", -1)):  # no rig, Right = +X
        arm, leg = box[side + " Arm"], box[side + " Leg"]
        shoulder_y = arm["hi"][1] - 0.25 * arm["size"][1]
        joint[side + " Shoulder"] = world((sign * ARM_MIN_X * SCALE, shoulder_y, arm["center"][2]))
        joint[side + " Hip"] = world((sign * ARM_MIN_X * SCALE, LEG_TOP_Y * SCALE, leg["center"][2]))
    joint["RootJoint"] = cframes["Torso"]

    motors = [  # (nome, part1, rotacao)
        ("RootJoint", "Torso", ROT_ROOT, "HumanoidRootPart"),
        ("Neck", "Head", ROT_ROOT, "Torso"),
        ("Right Shoulder", "Right Arm", ROT_R, "Torso"),
        ("Left Shoulder", "Left Arm", ROT_L, "Torso"),
        ("Right Hip", "Right Leg", ROT_R, "Torso"),
        ("Left Hip", "Left Leg", ROT_L, "Torso"),
    ]
    torso_centre_to_feet = cframes["Torso"][1] - (feet_y + oy)
    leg_len = max(sizes["Left Leg"][1], sizes["Right Leg"][1])
    hip_height = torso_centre_to_feet - leg_len - sizes["HumanoidRootPart"][1] / 2
    return {"box": box, "cframes": cframes, "sizes": sizes, "joint": joint, "motors": motors,
            "hip_height": round(hip_height, 4), "offset": off, "feet_y": feet_y + oy,
            "torso_to_feet": torso_centre_to_feet, "leg_len": leg_len}


def _num(v):
    text = "%.7g" % v
    return "0" if text in ("-0", "0") else text


def _cframe_xml(tag, pos, rot=(1, 0, 0, 0, 1, 0, 0, 0, 1), ind="\t\t\t\t\t"):
    names = ("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")
    body = "".join("%s\t<%s>%s</%s>\n" % (ind, n, _num(v), n) for n, v in zip(("X", "Y", "Z"), pos))
    body += "".join("%s\t<%s>%s</%s>\n" % (ind, n, _num(v), n) for n, v in zip(names, rot))
    return '%s<CoordinateFrame name="%s">\n%s%s</CoordinateFrame>\n' % (ind, tag, body, ind)


def _content(name, asset_id):
    if not asset_id:
        return '<Content name="%s"><null></null></Content>' % name
    return '<Content name="%s"><url>%s</url></Content>' % (name, asset_id)


def normalise_id(value):
    value = str(value or "").strip()
    if not value:
        return ""
    return value if value.startswith("rbxassetid://") else "rbxassetid://" + re.sub(r"\D", "", value)


def part_textures(ids, name):
    """Mapas PBR de uma peca: os compartilhados (`textures`) com override opcional em `part_textures[peca]`."""
    maps = {k: normalise_id(ids["textures"].get(k)) for k in MAP_NAMES}
    for k, v in ids.get("part_textures", {}).get(name, {}).items():
        if k in MAP_NAMES and normalise_id(v):
            maps[k] = normalise_id(v)
    return maps


def surface_appearance_xml(maps, ind="\t\t\t"):
    return ('%s<Item class="SurfaceAppearance" referent="RBX%s">\n%s\t<Properties>\n'
            '%s\t\t%s\n%s\t\t%s\n%s\t\t%s\n%s\t\t%s\n'
            '%s\t\t<string name="Name">SurfaceAppearance</string>\n'
            '%s\t</Properties>\n%s</Item>\n') % (
                ind, uuid.uuid4().hex, ind,
                ind, _content("ColorMap", maps["ColorMap"]), ind, _content("MetalnessMap", maps["MetalnessMap"]),
                ind, _content("NormalMap", maps["NormalMap"]), ind, _content("RoughnessMap", maps["RoughnessMap"]),
                ind, ind, ind)


def build_visuals_rbxmx(rig, ids):
    """Template so-visual: 6 MeshParts, sem Humanoid/Motor6D/Attachments (nao e um rig)."""
    out = ['<?xml version="1.0" encoding="utf-8"?>\n',
           '<roblox xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n',
           '\t<Item class="Model" referent="RBX%s">\n\t\t<Properties>\n' % uuid.uuid4().hex,
           '\t\t\t<string name="Name">MonsterMeshyVisuals</string>\n\t\t</Properties>\n']
    for name in PART_NAMES:
        size, cf = rig["sizes"][name], rig["cframes"][name]
        maps = part_textures(ids, name)
        out.append(('\t\t<Item class="MeshPart" referent="RBX%s">\n\t\t\t<Properties>\n'
                    '\t\t\t\t<bool name="Anchored">true</bool>\n%s\t\t\t\t<bool name="CanCollide">false</bool>\n'
                    '\t\t\t\t<bool name="CanQuery">false</bool>\n\t\t\t\t<bool name="CanTouch">false</bool>\n'
                    '\t\t\t\t<bool name="Massless">true</bool>\n\t\t\t\t<token name="Material">256</token>\n'
                    '\t\t\t\t<token name="CollisionFidelity">2</token>\n\t\t\t\t<token name="RenderFidelity">1</token>\n'
                    '\t\t\t\t%s\n\t\t\t\t%s\n'
                    '\t\t\t\t<Vector3 name="size"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>\n'
                    '\t\t\t\t<string name="Name">%s</string>\n\t\t\t</Properties>\n') % (
                        uuid.uuid4().hex, _cframe_xml("CFrame", cf, ind="\t\t\t\t"),
                        _content("MeshId", normalise_id(ids["meshes"].get(name))),
                        _content("TextureID", normalise_id(ids.get("texture_ids", {}).get(name))),
                        _num(size[0]), _num(size[1]), _num(size[2]), name))
        if maps["ColorMap"]:
            out.append(surface_appearance_xml(maps, ind="\t\t\t"))
        out.append("\t\t</Item>\n")
    out.append("\t</Item>\n</roblox>\n")
    return "".join(out)


def build_rbxmx(rig, ids):
    ref = {n: "RBX" + uuid.uuid4().hex for n in PART_NAMES + ["HumanoidRootPart"]}
    out = ['<?xml version="1.0" encoding="utf-8"?>\n',
           '<roblox xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n',
           '\t<Meta name="ExplicitAutoJoints">true</Meta>\n\t<External>null</External>\n\t<External>nil</External>\n',
           '\t<Item class="Model" referent="RBX%s">\n\t\t<Properties>\n' % uuid.uuid4().hex,
           '\t\t\t<Ref name="PrimaryPart">%s</Ref>\n' % ref["HumanoidRootPart"],
           '\t\t\t<string name="Name">R6 Monster Meshy</string>\n\t\t</Properties>\n']
    def attachments(part):
        std = STD_SIZE[part]
        size = rig["sizes"][part]
        text = ""
        for name, (x, y, z) in ATTACHMENTS[part].items():
            pos = (x * size[0] / std[0], y * size[1] / std[1], z * size[2] / std[2])
            text += ('\t\t<Item class="Attachment" referent="RBX%s">\n\t\t\t<Properties>\n%s'
                     '\t\t\t\t<bool name="Visible">false</bool>\n\t\t\t\t<string name="Name">%s</string>\n'
                     '\t\t\t</Properties>\n\t\t</Item>\n') % (uuid.uuid4().hex, _cframe_xml("CFrame", pos), name)
        return text

    def motor(name, part0, part1, rot):
        j = rig["joint"][name]
        c0 = tuple(j[k] - rig["cframes"][part0][k] for k in range(3))
        c1 = tuple(j[k] - rig["cframes"][part1][k] for k in range(3))
        return ('\t\t<Item class="Motor6D" referent="RBX%s">\n\t\t\t<Properties>\n'
                '\t\t\t\t<float name="DesiredAngle">0</float>\n\t\t\t\t<float name="MaxVelocity">0.1</float>\n%s%s'
                '\t\t\t\t<bool name="Enabled">true</bool>\n\t\t\t\t<Ref name="Part0">%s</Ref>\n'
                '\t\t\t\t<Ref name="Part1">%s</Ref>\n\t\t\t\t<string name="Name">%s</string>\n'
                '\t\t\t</Properties>\n\t\t</Item>\n') % (
                    uuid.uuid4().hex, _cframe_xml("C0", c0, rot), _cframe_xml("C1", c1, rot),
                    ref[part0], ref[part1], name)

    collide = {"Head": True, "Torso": True}
    motor_by_child = {m[1]: m for m in rig["motors"]}

    # Humanoid vai primeiro, como no template.
    out.append(
        '\t\t<Item class="Humanoid" referent="RBX%s">\n\t\t\t<Properties>\n'
        '\t\t\t\t<float name="HipHeight">%s</float>\n\t\t\t\t<token name="RigType">0</token>\n'
        '\t\t\t\t<float name="MaxHealth">100</float>\n\t\t\t\t<float name="Health_XML">100</float>\n'
        '\t\t\t\t<float name="WalkSpeed">16</float>\n\t\t\t\t<float name="NameDisplayDistance">0</float>\n'
        '\t\t\t\t<token name="DisplayDistanceType">2</token>\n\t\t\t\t<token name="HealthDisplayType">2</token>\n'
        '\t\t\t\t<string name="Name">Humanoid</string>\n\t\t\t</Properties>\n'
        '\t\t\t<Item class="Animator" referent="RBX%s"><Properties><string name="Name">Animator</string>'
        '</Properties></Item>\n\t\t</Item>\n' % (uuid.uuid4().hex, _num(rig["hip_height"]), uuid.uuid4().hex))

    for name in ["HumanoidRootPart"] + PART_NAMES:
        size, cf = rig["sizes"][name], rig["cframes"][name]
        body = ""
        if name == "HumanoidRootPart":
            out.append(('\t\t<Item class="Part" referent="%s">\n\t\t\t<Properties>\n'
                        '\t\t\t\t<bool name="Anchored">true</bool>\n%s\t\t\t\t<bool name="CanCollide">false</bool>\n'
                        '\t\t\t\t<bool name="CanQuery">true</bool>\n\t\t\t\t<bool name="CanTouch">true</bool>\n'
                        '\t\t\t\t<token name="Material">256</token>\n\t\t\t\t<float name="Transparency">1</float>\n'
                        '\t\t\t\t<Vector3 name="size"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>\n'
                        '\t\t\t\t<string name="Name">HumanoidRootPart</string>\n\t\t\t</Properties>\n') % (
                            ref[name], _cframe_xml("CFrame", cf, ind="\t\t\t\t"),
                            _num(size[0]), _num(size[1]), _num(size[2])))
            out.append(motor("RootJoint", "HumanoidRootPart", "Torso", ROT_ROOT))
            out.append(attachments(name))
            out.append("\t\t</Item>\n")
            continue
        mesh_id = normalise_id(ids["meshes"].get(name))
        out.append(('\t\t<Item class="MeshPart" referent="%s">\n\t\t\t<Properties>\n'
                    '\t\t\t\t<bool name="Anchored">false</bool>\n%s\t\t\t\t<bool name="CanCollide">%s</bool>\n'
                    '\t\t\t\t<bool name="CanQuery">true</bool>\n\t\t\t\t<bool name="CanTouch">true</bool>\n'
                    '\t\t\t\t<bool name="CastShadow">true</bool>\n\t\t\t\t<bool name="Massless">false</bool>\n'
                    '\t\t\t\t<token name="Material">256</token>\n'
                    '\t\t\t\t<Color3uint8 name="Color3uint8">4288914085</Color3uint8>\n'
                    '\t\t\t\t<token name="CollisionFidelity">2</token>\n\t\t\t\t<token name="RenderFidelity">1</token>\n'
                    '\t\t\t\t%s\n\t\t\t\t%s\n'
                    '\t\t\t\t<Vector3 name="size"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>\n'
                    '\t\t\t\t<string name="Name">%s</string>\n\t\t\t</Properties>\n') % (
                        ref[name], _cframe_xml("CFrame", cf, ind="\t\t\t\t"),
                        "true" if collide.get(name) else "false", _content("MeshId", mesh_id),
                        _content("TextureID", normalise_id(ids.get("texture_ids", {}).get(name))),
                        _num(size[0]), _num(size[1]), _num(size[2]), name))
        if name == "Torso":
            for m in rig["motors"]:
                if m[3] == "Torso":
                    out.append(motor(m[0], "Torso", m[1], m[2]))
        out.append(attachments(name))
        maps = part_textures(ids, name)
        if maps["ColorMap"]:
            out.append(surface_appearance_xml(maps))
        out.append("\t\t</Item>\n")
    out.append("\t</Item>\n</roblox>\n")
    return "".join(out)


# =============================================================================
# Verificacao (le o .rbxmx ja gravado, sem reaproveitar as variaveis de construcao)
# =============================================================================
def _prop(item, tag, name):
    return item.find("Properties/%s[@name='%s']" % (tag, name))


def _cf(el):
    v = {c.tag: float(c.text) for c in el}
    return (v["X"], v["Y"], v["Z"]), tuple(v[k] for k in ("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"))


def verify(rbxmx_path, parts, rig):
    problems = []
    model = ET.parse(rbxmx_path).getroot().find("Item")
    items = {}
    for it in model.findall("Item"):
        n = _prop(it, "string", "Name")
        items[n.text] = it
    cfg = ANIM_CONFIG.read_text()
    required_parts = re.findall(r'"([^"]+)"', re.search(r"RequiredParts\s*=\s*\{(.*?)\}", cfg, re.S).group(1))
    required_motors = re.findall(r'"([^"]+)"', re.search(r"RequiredMotors\s*=\s*\{(.*?)\}", cfg, re.S).group(1))
    for n in required_parts:
        if n not in items:
            problems.append("parte ausente: " + n)
    referents = {it.get("referent"): _prop(it, "string", "Name").text for it in model.iter("Item")
                 if _prop(it, "string", "Name") is not None}
    by_name = {}
    for n, it in items.items():
        if it.get("class") in ("Part", "MeshPart"):
            by_name[n] = (_cf(_prop(it, "CoordinateFrame", "CFrame")), [float(c.text) for c in _prop(it, "Vector3", "size")])
    found = {}
    for it in model.iter("Item"):
        if it.get("class") != "Motor6D":
            continue
        name = _prop(it, "string", "Name").text
        found[name] = it
        p0 = referents[_prop(it, "Ref", "Part0").text]
        p1 = referents[_prop(it, "Ref", "Part1").text]
        (c0p, c0r), (c1p, c1r) = _cf(_prop(it, "CoordinateFrame", "C0")), _cf(_prop(it, "CoordinateFrame", "C1"))
        (a, _), (b, _) = by_name[p0][0], by_name[p1][0]
        # Partes sem rotacao: posicao mundial da junta pelos dois lados tem que coincidir.
        wa = tuple(a[k] + c0p[k] for k in range(3))
        wb = tuple(b[k] + c1p[k] for k in range(3))
        err = max(abs(wa[k] - wb[k]) for k in range(3))
        if err > 1e-4:
            problems.append("%s: C0/C1 nao coincidem em pose de repouso (erro %.5f)" % (name, err))
        if max(abs(c0r[k] - c1r[k]) for k in range(9)) > 1e-6:
            problems.append("%s: rotacao de C0 e C1 diferentes" % name)
    for n in required_motors:
        if n not in found:
            problems.append("Motor6D ausente: " + n)
    if model.find("Item[@class='Humanoid']/Item[@class='Animator']") is None:
        problems.append("sem Animator")
    for name, part in parts.items():
        if part["open_edges"]:
            problems.append("%s: malha com %d arestas abertas depois das tampas" % (name, part["open_edges"]))
    if abs(rig["feet_y"] - RIG_GROUND_Y) > 1e-4:
        problems.append("pes fora do chao")
    return problems


# =============================================================================
def verify_visuals(path, ids):
    problems = []
    model = ET.parse(path).getroot().find("Item")
    found = {}
    for it in model.findall("Item"):
        found[_prop(it, "string", "Name").text] = it
    for name in PART_NAMES:
        it = found.get(name)
        if it is None or it.get("class") != "MeshPart":
            problems.append("template visual sem MeshPart '%s'" % name)
            continue
        want = normalise_id(ids["meshes"].get(name))
        content = _prop(it, "Content", "MeshId")
        url = content.find("url")
        if (url.text if url is not None else "") != want:
            problems.append("%s: MeshId do template diferente do asset_ids.json" % name)
        has_sa = it.find("Item[@class='SurfaceAppearance']") is not None
        if has_sa != bool(part_textures(ids, name)["ColorMap"]):
            problems.append("%s: SurfaceAppearance do template inconsistente com asset_ids.json" % name)
    extra = set(found) - set(PART_NAMES)
    if extra:
        problems.append("template visual com itens extras: %s" % sorted(extra))
    return problems


def prepare_textures():
    try:
        from PIL import Image, ImageChops
    except ImportError:
        print("  (Pillow ausente: pulei os PNGs de textura; use os originais de model/)")
        return []
    (OUT_DIR / "textures").mkdir(parents=True, exist_ok=True)
    done = []
    for key, src in TEXTURE_SOURCES.items():
        img = Image.open(src)
        if max(img.size) > TEXTURE_PX:
            img = img.resize((TEXTURE_PX, TEXTURE_PX), Image.LANCZOS)
        if key in ("MetalnessMap", "RoughnessMap") and img.mode == "RGB":
            r, g, b = img.split()
            if not ImageChops.difference(r, g).getbbox() and not ImageChops.difference(r, b).getbbox():
                img = r  # cinza puro: guarda 1 canal
        dest = OUT_DIR / "textures" / (key + ".png")
        img.save(dest, optimize=True)
        done.append("%s (%dx%d, %s)" % (dest.name, img.size[0], img.size[1], img.mode))
    return done


def main():
    if not FBX_PATH.exists():
        raise SystemExit("FBX nao encontrado: %s" % FBX_PATH)
    mesh = read_fbx_mesh(FBX_PATH)
    print("FBX: %s" % dict(mesh["census"]))
    print("  vertices=%d quads=%d skin/esqueleto=%s" % (len(mesh["verts"]), len(mesh["quads"]),
                                                          "SIM" if mesh["has_skin"] else "nao"))
    if mesh["has_skin"]:
        raise SystemExit("O FBX tem Deformer/skin; este script assume malha estatica unica.")

    labels = classify(mesh)
    (OUT_DIR / "parts").mkdir(parents=True, exist_ok=True)
    parts = {}
    for name in PART_NAMES:
        ids = [i for i, l in enumerate(labels) if l == name]
        parts[name] = build_part(mesh, ids)
        write_obj(OUT_DIR / "parts" / (FILE_NAMES[name] + ".obj"), FILE_NAMES[name], parts[name])
        p = parts[name]
        print("  %-9s quads=%-5d tampas=%d tris=%-5d fechada=%s" % (
            name, p["quads"], p["caps"], len(p["tris"]), "sim" if not p["open_edges"] else "NAO"))

    print("Texturas:")
    for line in prepare_textures():
        print("  " + line)

    ids_path = OUT_DIR / "asset_ids.json"
    ids = {"meshes": {n: "" for n in PART_NAMES}, "textures": {k: "" for k in MAP_NAMES}}
    if ids_path.exists():
        saved = json.loads(ids_path.read_text())
        for key, value in saved.items():  # preserva chaves opcionais (texture_ids, part_textures)
            if isinstance(value, dict) and key in ids:
                ids[key].update(value)
            else:
                ids[key] = value
    ids_path.write_text(json.dumps(ids, indent=2, ensure_ascii=False) + "\n")

    rig = compute_rig(parts)
    RIG_PATH.write_text(build_rbxmx(rig, ids), encoding="utf-8")
    height = rig["box"]["Head"]["hi"][1] - rig["box"]["Left Leg"]["lo"][1]
    print("Rig: %s" % RIG_PATH.relative_to(ROOT))
    print("  altura=%.3f studs  HipHeight=%s  perna=%.3f  torso->pes=%.3f" % (
        height, rig["hip_height"], rig["leg_len"], rig["torso_to_feet"]))
    for n in PART_NAMES:
        print("  %-9s size=(%.3f, %.3f, %.3f)" % ((n,) + tuple(rig["sizes"][n])))

    VISUALS_PATH.write_text(build_visuals_rbxmx(rig, ids), encoding="utf-8")
    print("Visuais para o monstro atual: %s" % VISUALS_PATH.relative_to(ROOT))

    problems = verify(RIG_PATH, parts, rig) + verify_visuals(VISUALS_PATH, ids)
    if problems:
        print("\nFALHOU a verificacao:")
        for p in problems:
            print("  - " + p)
        sys.exit(1)
    missing = [n for n, v in ids["meshes"].items() if not v]
    print("\nVerificacao OK (juntas, assinatura R6 do MonsterAnimationConfig, malhas fechadas).")
    if missing:
        print("Faltam ids de mesh em %s -> importe os OBJ no Studio e rode este script de novo." % ids_path.relative_to(ROOT))


if __name__ == "__main__":
    main()
