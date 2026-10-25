"""Bounded ELF/Mach-O/PE file ranges for secret-safe artifact diagnostics.

These are file offsets, never matched string contents. Malformed/unsupported
inputs have no trusted ranges and cannot acquire an upstream classification.
"""

from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass


@dataclass(frozen=True)
class Section:
    name: str
    offset: int
    size: int
    slice: int = 0


def _name(value: bytes) -> str:
    return value.split(b"\0", 1)[0].decode("ascii", errors="replace")


def sections(data: bytes) -> tuple[str, list[Section]]:
    try:
        if data[:4] == b"\x7fELF" and data[4:6] == b"\x02\x01":
            offset = struct.unpack_from("<Q", data, 40)[0]
            stride, count, names_index = struct.unpack_from("<HHH", data, 58)
            if stride < 64 or count > 4096 or names_index >= count:
                return "ELF", []
            headers = [struct.unpack_from("<IIQQQQIIQQ", data, offset + i * stride)
                       for i in range(count)]
            names = headers[names_index]
            strings = data[names[4]:names[4] + names[5]]
            result = [Section(_name(strings[h[0]:]), h[4], h[5]) for h in headers
                      if h[1] != 8 and h[4] + h[5] <= len(data)]
            return "ELF", result
        if data[:2] == b"MZ":
            pe = struct.unpack_from("<I", data, 60)[0]
            if data[pe:pe + 4] != b"PE\0\0":
                return "PE", []
            count = struct.unpack_from("<H", data, pe + 6)[0]
            optional = struct.unpack_from("<H", data, pe + 20)[0]
            if count > 4096:
                return "PE", []
            start = pe + 24 + optional
            result = []
            for i in range(count):
                pos = start + i * 40
                size, offset = struct.unpack_from("<II", data, pos + 16)
                result.append(Section(_name(data[pos:pos + 8]), offset, size))
            return "PE", [s for s in result if s.offset + s.size <= len(data)]
        if data[:4] == b"\xca\xfe\xba\xbe":
            count = struct.unpack_from(">I", data, 4)[0]
            if count > 16:
                return "Mach-O", []
            result = []
            for i in range(count):
                _, _, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + i * 20)
                if offset + size > len(data):
                    return "Mach-O", []
                result.extend(_mach_sections(data[offset:offset + size], offset, i))
            return "Mach-O", result
        if data[:4] == b"\xcf\xfa\xed\xfe":
            return "Mach-O", _mach_sections(data, 0, 0)
    except (struct.error, IndexError, ValueError):
        pass
    return "unknown", []


def _mach_sections(data: bytes, base: int, slice_index: int) -> list[Section]:
    if data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("unsupported Mach-O slice")
    count, command_bytes = struct.unpack_from("<II", data, 16)
    if count > 4096 or 32 + command_bytes > len(data):
        raise ValueError("invalid load commands")
    pos = 32
    result = []
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, pos)
        if size < 8 or pos + size > 32 + command_bytes:
            raise ValueError("invalid load command")
        if command == 0x19:  # LC_SEGMENT_64
            number = struct.unpack_from("<I", data, pos + 64)[0]
            if 72 + number * 80 > size:
                raise ValueError("invalid section table")
            for i in range(number):
                start = pos + 72 + i * 80
                section_name = _name(data[start:start + 16])
                segment = _name(data[start + 16:start + 32])
                extent, offset = struct.unpack_from("<QI", data, start + 40)
                flags = struct.unpack_from("<I", data, start + 64)[0]
                if flags & 0xff in (1, 0xc, 0x12):  # zerofill has no file data
                    continue
                if offset + extent > len(data):
                    raise ValueError("invalid section extent")
                result.append(Section(f"{segment},{section_name}", base + offset,
                                      extent, slice_index))
        elif command == 2:  # LC_SYMTAB: includes STABS/N_OSO build paths
            symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", data, pos + 8)
            for name, offset, extent in (("symbol-table", symoff, nsyms * 16),
                                         ("symbol-strings", stroff, strsize)):
                if offset + extent > len(data):
                    raise ValueError("invalid symbol table")
                result.append(Section(name, base + offset, extent, slice_index))
        pos += size
    return result


def loadable_fingerprint(data: bytes, ranges: list[Section]) -> str:
    """Mach-O contents unchanged by debug strip, install-name or ad-hoc signing.

    Includes all file-backed sections except DWARF and symbol metadata, not
    merely code. The ordered slice index keeps universal architectures distinct.
    """
    digest = hashlib.sha256()
    for section in ranges:
        if "," not in section.name or section.name.startswith("__DWARF,"):
            continue
        digest.update(f"{section.slice}:{section.name}:{section.size}\0".encode())
        digest.update(data[section.offset:section.offset + section.size])
    return digest.hexdigest()


def macho_slices(data: bytes) -> list[bytes]:
    """Validated 64-bit slices; offsets in each returned slice start at zero."""
    slices = [data]
    if data[:4] == b"\xca\xfe\xba\xbe":
        count = struct.unpack_from(">I", data, 4)[0]
        if not 0 < count <= 16:
            raise ValueError("invalid Mach-O slice count")
        slices = []
        occupied = []
        for i in range(count):
            _, _, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + i * 20)
            if (offset < 8 + count * 20 or size < 32 or offset + size > len(data)
                    or any(a < offset + size and offset < b for a, b in occupied)):
                raise ValueError("invalid Mach-O slice extent")
            occupied.append((offset, offset + size))
            slices.append(data[offset:offset + size])
    for slice_data in slices:
        if slice_data[:4] != b"\xcf\xfa\xed\xfe":
            raise ValueError("unsupported Mach-O runtime contract")
        _mach_sections(slice_data, 0, 0)  # validates all command/table ranges
    return slices


def macho_linkedit_fingerprint(data: bytes) -> str:
    """Dyld data, external symbols and alias targets are ABI, not debug metadata.

    Symbol-name-only nm output can miss a strip tool corrupting the target
    string-table index of an indirect export. Ignore physical table offsets,
    but require these runtime meanings to survive exactly, per architecture.
    """
    digest = hashlib.sha256()
    for slice_data in macho_slices(data):
        digest.update(slice_data[4:16])  # CPU/subtype/file type
        count = struct.unpack_from("<I", slice_data, 16)[0]
        pos = 32
        symbols = []
        for _ in range(count):
            command, size = struct.unpack_from("<II", slice_data, pos)
            if command == 2:
                symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", slice_data, pos + 8)
                table = slice_data[stroff:stroff + strsize]
                for i in range(nsyms):
                    name, kind, section, description, target = struct.unpack_from("<IBBHQ", slice_data, symoff + i * 16)
                    if not kind & 0xe0 and kind & 1:  # N_EXT, not STABS
                        if name >= strsize:
                            raise ValueError("invalid external symbol")
                        value = str(target).encode()
                        if kind & 0xe == 0xa:  # N_INDR: value is a string index
                            if target >= strsize:
                                raise ValueError("invalid indirect export")
                            value = table[target:].split(b"\0", 1)[0]
                        symbols.append((table[name:].split(b"\0", 1)[0],
                                        kind, section, description, value))
            elif command in (0x80000033, 0x80000034, 0x22, 0x80000022):
                # Export trie / chained fixups, or all five dyld-info blobs:
                # rebase, bind, weak bind, lazy bind, export. Physical offsets
                # can change on strip; their runtime bytecode cannot.
                fields = (8,) if command in (0x80000033, 0x80000034) else range(8, 48, 8)
                for field in fields:
                    offset, extent = struct.unpack_from("<II", slice_data, pos + field)
                    if offset + extent > len(slice_data):
                        raise ValueError("invalid dyld data")
                    digest.update(struct.pack("<II", command, field))
                    digest.update(slice_data[offset:offset + extent])
            pos += size
        for name, kind, section, description, value in sorted(symbols):
            digest.update(name + b"\0" + struct.pack("<BBH", kind, section, description) + value + b"\0")
    return digest.hexdigest()


def macho_indirect_fingerprint(data: bytes) -> str:
    """Preserve indirect-table targets, allowing strip to renumber nlist entries.

    Separate from the pinned upstream LINKEDIT fingerprint so its policy and
    recorded digests remain unchanged. LOCAL/ABS sentinels are runtime values,
    not indexes. Normal targets include full symbol and N_INDR alias meaning.
    """
    digest = hashlib.sha256()
    for slice_data in macho_slices(data):
        digest.update(slice_data[4:16])
        _, ranges = sections(slice_data)
        symbol_table = next((s for s in ranges if s.name == "symbol-table"), None)
        strings = next((s for s in ranges if s.name == "symbol-strings"), None)
        names = slice_data[strings.offset:strings.offset + strings.size] if strings is not None else b""
        def symbol_name(at: int) -> bytes:
            end = names.find(b"\0", at) if at < len(names) else -1
            if end < 0:
                raise ValueError("invalid indirect symbol name")
            return names[at:end]
        pos = 32
        for _ in range(struct.unpack_from("<I", slice_data, 16)[0]):
            command, size = struct.unpack_from("<II", slice_data, pos)
            if command == 0xb:  # LC_DYSYMTAB
                if size != 80:
                    raise ValueError("invalid dynamic symbol command")
                offset, count = struct.unpack_from("<II", slice_data, pos + 56)
                if offset + count * 4 > len(slice_data):
                    raise ValueError("invalid indirect table extent")
                digest.update(struct.pack("<I", count))
                for index in range(count):
                    target = struct.unpack_from("<I", slice_data, offset + index * 4)[0]
                    if target & 0xc0000000:
                        if target not in (0x80000000, 0x40000000, 0xc0000000):
                            raise ValueError("invalid indirect special target")
                        digest.update(b"special" + struct.pack("<I", target))
                        continue
                    if symbol_table is None or strings is None or target >= symbol_table.size // 16:
                        raise ValueError("invalid indirect symbol index")
                    name, kind, section, description, value = struct.unpack_from(
                        "<IBBHQ", slice_data, symbol_table.offset + target * 16)
                    if kind & 0xe0:
                        raise ValueError("indirect target is a debug record")
                    target_value = symbol_name(value) if kind & 0xe == 0xa else str(value).encode()
                    digest.update(b"symbol" + symbol_name(name) + b"\0"
                                  + struct.pack("<BBH", kind, section, description) + target_value + b"\0")
            pos += size
    return digest.hexdigest()
