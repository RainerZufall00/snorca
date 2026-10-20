"""Writes the models the UI tests import into a folder:
- Kopftest.3mf: Orca-style project, 'Sockel' on extruder 1 and 'Turm' on 3
- 3DBenchy.3mf: downloaded from OrcaSlicer's handy_models (pinned commit)
"""
import os
import sys
import urllib.request
import zipfile

ORCA = "https://raw.githubusercontent.com/Snapmaker/OrcaSlicer/89311782298309040ee28b9a183f33f0f5477b15/resources/handy_models/"


def box(x, y, z):
    v = [(0, 0, 0), (x, 0, 0), (x, y, 0), (0, y, 0), (0, 0, z), (x, 0, z), (x, y, z), (0, y, z)]
    f = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4),
         (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)]
    verts = "".join(f'<vertex x="{a}" y="{b}" z="{c}"/>' for a, b, c in v)
    tris = "".join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in f)
    return f"<mesh><vertices>{verts}</vertices><triangles>{tris}</triangles></mesh>"


def heads_3mf(path):
    model = f"""<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
<resources>
<object id="1" type="model" name="Sockel">{box(40, 40, 6)}</object>
<object id="2" type="model" name="Turm">{box(12, 12, 30)}</object>
</resources>
<build>
<item objectid="1" transform="1 0 0 0 1 0 0 0 1 60 80 0"/>
<item objectid="2" transform="1 0 0 0 1 0 0 0 1 170 120 0"/>
</build>
</model>"""
    settings = """<?xml version="1.0" encoding="UTF-8"?>
<config>
<object id="1"><metadata key="name" value="Sockel"/><metadata key="extruder" value="1"/></object>
<object id="2"><metadata key="name" value="Turm"/><metadata key="extruder" value="3"/></object>
</config>"""
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("3D/3dmodel.model", model)
        z.writestr("Metadata/model_settings.config", settings)


def main(folder, *download):
    os.makedirs(folder, exist_ok=True)
    heads_3mf(os.path.join(folder, "Kopftest.3mf"))
    for name in download:
        urllib.request.urlretrieve(ORCA + name, os.path.join(folder, name))
    print("models:", sorted(os.listdir(folder)))


if __name__ == "__main__":
    main(*sys.argv[1:])
