"""Builds data/map.txt - the HANTU mansion floorplan.

Legend:
  #  wall
  .  floor
  S  player spawn
  E  exit
  ?  floor with a book
"""

W, H = 35, 27
grid = [["#" for _ in range(W)] for _ in range(H)]


def carve(x0, y0, x1, y1, ch="."):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            grid[y][x] = ch


# Main corridors (cross shape)
carve(16, 1, 18, 25)
carve(1, 12, 33, 14)

# Rooms (interior rectangles), two per corner
rooms = {
    "TL-A": (2, 2, 14, 5),
    "TL-B": (2, 7, 14, 10),
    "TR-A": (20, 2, 32, 5),
    "TR-B": (20, 7, 32, 10),
    "BL-A": (2, 16, 14, 19),
    "BL-B": (2, 21, 14, 24),
    "BR-A": (20, 16, 32, 19),
    "BR-B": (20, 21, 32, 24),
}
for x0, y0, x1, y1 in rooms.values():
    carve(x0, y0, x1, y1)

# Doors between rooms and middle corridor
doors = [(15, 3), (15, 8), (19, 3), (19, 8),
         (15, 17), (15, 22), (19, 17), (19, 22)]
for x, y in doors:
    carve(x, y, x, y)

# Spawn / exit
grid[23][17] = "S"
grid[25][17] = "E"
# Doorway through the south wall so the exit opens onto moonlight
grid[26][17] = "."

# 3 books per room + 1 in the corridor
book_spots = []
for x0, y0, x1, y1 in rooms.values():
    cy = y0 + 1
    for x in (x0 + 2, x0 + 6, x0 + 10):
        book_spots.append((x, cy))
book_spots.append((8, 13))

assert len(book_spots) == 25, len(book_spots)
for x, y in book_spots:
    assert grid[y][x] in (".", "S", "E"), (x, y, grid[y][x])
    grid[y][x] = "?"

# Sanity: all book spots reachable from spawn through floor cells
from collections import deque

sx, sy = 17, 23
seen = {(sx, sy)}
q = deque([(sx, sy)])
while q:
    x, y = q.popleft()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in seen and grid[ny][nx] != "#":
            seen.add((nx, ny))
            q.append((nx, ny))

for x, y in book_spots + [(17, 2), (17, 25), (17, 26)]:
    assert (x, y) in seen, ("unreachable", x, y)

with open("data/map.txt", "w", encoding="utf-8", newline="\n") as f:
    for row in grid:
        f.write("".join(row) + "\n")

print("\n".join("".join(r) for r in grid))
print("reachable cells:", len(seen))
