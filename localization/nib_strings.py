"""Read static localization pairs from the installed NIBArchive resources.

Only the archive object/value tables are decoded. No nib is instantiated or
written, and unsupported archive versions fail explicitly.
"""

from pathlib import Path
import struct


def localized_nib_strings(path: Path) -> dict[str, str]:
    data = path.read_bytes()
    if not data.startswith(b"NIBArchive"):
        return {}
    header = struct.unpack_from("<10I", data, 10)
    if header[0] != 1:
        raise ValueError(f"Unsupported NIBArchive version in {path.name}")
    cursor = header[5]

    def integer():
        nonlocal cursor
        result = 0
        for shift in range(0, 64, 7):
            byte = data[cursor]
            cursor += 1
            result |= (byte & 127) << shift
            if byte & 128:
                return result
        raise ValueError(f"Oversized NIBArchive integer in {path.name}")

    keys = []
    for _ in range(header[4]):
        length = integer()
        keys.append(data[cursor:cursor+length].decode("utf-8"))
        cursor += length
    if cursor != header[7]:
        raise ValueError(f"Inconsistent NIBArchive key table in {path.name}")
    values = []
    numeric = {0: "<b", 1: "<h", 2: "<i", 3: "<q", 6: "<f", 7: "<d", 10: "<I"}
    for _ in range(header[6]):
        key = keys[integer()]
        kind = data[cursor]
        cursor += 1
        if kind == 8:
            length = integer()
            value = data[cursor:cursor+length]
            cursor += length
            try:
                value = value.decode("utf-8")
            except UnicodeDecodeError:
                value = None
        elif kind in numeric:
            fmt = numeric[kind]
            value = struct.unpack_from(fmt, data, cursor)[0]
            cursor += struct.calcsize(fmt)
        elif kind in (4, 5, 9):
            value = {4: True, 5: False, 9: None}[kind]
        else:
            raise ValueError(f"Unsupported NIBArchive value type {kind} in {path.name}")
        values.append((key, kind, value))
    if cursor != header[9]:
        raise ValueError(f"Inconsistent NIBArchive value table in {path.name}")
    cursor = header[3]
    objects = []
    for _ in range(header[2]):
        integer()  # Class index is unnecessary for static NSString references.
        start = integer()
        count = integer()
        objects.append({key: (kind, value) for key, kind, value in values[start:start+count]})
    if cursor != header[5]:
        raise ValueError(f"Inconsistent NIBArchive object table in {path.name}")
    result = {}
    for item in objects:
        if "NSKey" not in item or "NSDev" not in item:
            continue
        if item["NSKey"][0] != 10 or item["NSDev"][0] != 10:
            continue
        key = objects[item["NSKey"][1]].get("NS.bytes", (None, None))[1]
        value = objects[item["NSDev"][1]].get("NS.bytes", (None, None))[1]
        if isinstance(key, str) and isinstance(value, str):
            result[key] = value
    return result
