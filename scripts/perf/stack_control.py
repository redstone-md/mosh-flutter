"""Small live stack-export loop; no application/fixture warmup is required."""
from pathlib import Path
import sys

from cpu_profile import CpuProfile


root = Path(sys.argv[1]).resolve()
CpuProfile(root, 'control', int(sys.argv[2]), seconds=12).finish()
print('Complete: selected-PID CPU data and caller export')
