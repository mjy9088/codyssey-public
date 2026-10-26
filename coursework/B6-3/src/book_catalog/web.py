from pathlib import Path
from typing import Final

from fastapi.templating import Jinja2Templates

PACKAGE_ROOT: Final = Path(__file__).parent
templates: Final = Jinja2Templates(directory=PACKAGE_ROOT / "templates")
