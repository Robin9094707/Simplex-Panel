from pathlib import Path
import math, struct, zlib

ROOT = Path(__file__).resolve().parents[1]
def png(path, size, accent):
    rows = []
    def inside(x, y, points):
        hit = False
        for i, (ax, ay) in enumerate(points):
            bx, by = points[i-1]
            if (ay > y) != (by > y) and x < (bx-ax)*(y-ay)/(by-ay)+ax: hit = not hit
        return hit
    wings = [[(.20,.34),(.78,.22),(.55,.48),(.37,.48)],[(.37,.54),(.55,.54),(.79,.37),(.58,.72),(.39,.78)]]
    for yy in range(size):
        row = bytearray([0])
        for xx in range(size):
            x,y=(xx+.5)/size,(yy+.5)/size
            glow=max(0,1-math.hypot(x-.75,y-.2))*.2
            color=tuple(int(c*(.06+glow)+b) for c,b in zip(accent,(7,14,27)))
            if any(inside(x,y,p) for p in wings): color=tuple(int(c*(1-y*.25)) for c in accent)
            row.extend(color)
        rows.append(bytes(row))
    def chunk(t,d):return struct.pack('!I',len(d))+t+d+struct.pack('!I',zlib.crc32(t+d)&0xffffffff)
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b''))
for name, rgb in [('AppIcon',(65,235,204)),('ServerIcon',(95,181,255)),('AmethystIcon',(185,139,255))]:
    png(ROOT/f'Panel/Assets.xcassets/{name}.appiconset/{name}.png',1024,rgb)
    png(ROOT/f'Panel/Assets.xcassets/Preview{name}.imageset/preview.png',180,rgb)
print('Simplex Wing icons generated.')
