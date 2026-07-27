"""Red Alert 2 / Tiberian Sun asset conversion helpers.

The implementation is original and based on public binary-format documentation.
It converts legacy indexed/voxel assets into ordinary Godot PNG/TRES resources.
"""

from .palette import Palette
from .shp_ts import ShpTsFile
from .hva import HvaFile
from .vxl import VxlFile

__all__ = ["Palette", "ShpTsFile", "HvaFile", "VxlFile"]
