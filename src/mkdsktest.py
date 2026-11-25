#!/usr/bin/env python3
"""Fabrique DSKTEST.DSK : disquette de test (EDSK) pour DSKTEST.BIN.

Usage : python3 mkdsktest.py DSKTEST.BIN DSKTEST.DSK

- format DATA d'AMSDOS (secteurs #C1-#C9, 512 octets), 42 pistes, 1 face ;
- DSKTEST.BIN (avec son en-tete AMSDOS) dans le catalogue -> RUN"DSKTEST.BIN"
- pistes speciales a contenu connu, relues et verifiees par DSKTEST.BIN.
  Les donnees d'un secteur (piste physique T, ID R) sont produites par le
  LFSR 16 bits de Galois (polynome #B400), graine ((T << 8) | R) xor #A55A,
  un octet = octet de poids faible APRES chaque pas.

Ce script doit rester coherent avec la table dk_tab de dsktest.asm.
"""
import struct
import sys

NTRACKS = 42


def lfsr_bytes(track, sector_id, length):
    s = ((track << 8) | sector_id) ^ 0xA55A
    out = bytearray()
    for _ in range(length):
        carry = s & 1
        s >>= 1
        if carry:
            s ^= 0xB400
        out.append(s & 0xFF)
    return bytes(out)


class Sector:
    def __init__(self, c, h, r, n, data, st1=0, st2=0):
        self.c, self.h, self.r, self.n = c, h, r, n
        self.data, self.st1, self.st2 = data, st1, st2


def data_track(track, fill=0xE5):
    return [Sector(track, 0, 0xC1 + i, 2, bytes([fill]) * 512) for i in range(9)]


def lfsr_sector(track, c, h, r, n, **kw):
    return Sector(c, h, r, n, lfsr_bytes(track, r, 128 << n), **kw)


def special_tracks():
    t = {}
    # 20, 40, 41 : format DATA standard, contenu connu
    for trk in (20, 40, 41):
        t[trk] = [lfsr_sector(trk, trk, 0, 0xC1 + i, 2) for i in range(9)]
    # 21 : 10 secteurs de 512
    t[21] = [lfsr_sector(21, 21, 0, 0xC1 + i, 2) for i in range(10)]
    # 22 : tailles 128 a 2048 (R = 1..5, N = 0..4)
    t[22] = [lfsr_sector(22, 22, 0, r, r - 1) for r in range(1, 6)]
    # 23 : un secteur de 4 Ko
    t[23] = [lfsr_sector(23, 23, 0, 0x51, 5)]
    # 24 : IDs non standard
    t[24] = [lfsr_sector(24, c, h, r, 2) for (c, h, r) in
             ((0x2A, 0, 0x01), (0xFF, 0xFF, 0xFF), (24, 1, 0xC1),
              (0, 0, 0), (0x80, 0x80, 0x80))]
    # 25 : secteurs #C2 et #C4 effaces (ST2 bit 6 = marque de donnees effacees)
    t[25] = [lfsr_sector(25, 25, 0, 0xC1 + i, 2, st2=(0x40 if i in (1, 3) else 0))
             for i in range(4)]
    # 26 : secteur #C2 avec erreur CRC dans les donnees (ST1 bit 5, ST2 bit 5)
    t[26] = [lfsr_sector(26, 26, 0, 0xC1 + i, 2,
                         st1=(0x20 if i == 1 else 0), st2=(0x20 if i == 1 else 0))
             for i in range(3)]
    # 27 : non formatee
    t[27] = []
    return t


def amsdos_tracks(binfile, name, ext):
    """Pistes 0.. : catalogue (blocs 0-1) + fichier a partir du bloc 2."""
    data = open(binfile, 'rb').read()
    assert len(data) <= 16384, "fichier trop gros pour une seule entree"
    nblocks = (len(data) + 1023) // 1024
    records = (len(data) + 127) // 128
    entry = bytes([0]) + name.ljust(8).encode() + ext.ljust(3).encode()
    entry += bytes([0, 0, 0, records])
    entry += bytes(range(2, 2 + nblocks)).ljust(16, b'\0')
    directory = entry + b'\xE5' * (2048 - 32)
    image = directory + data.ljust(nblocks * 1024, b'\0')
    nsect = len(image) // 512
    tracks = {}
    for ls in range(nsect):
        trk, sec = divmod(ls, 9)
        tracks.setdefault(trk, data_track(trk))
        tracks[trk][sec].data = image[ls * 512:(ls + 1) * 512]
    return tracks


def build(binfile, out):
    tracks = {trk: data_track(trk) for trk in range(NTRACKS)}
    tracks.update(amsdos_tracks(binfile, 'DSKTEST', 'BIN'))
    sp = special_tracks()
    assert all(trk >= 2 for trk in sp), "conflit avec le catalogue"
    tracks.update(sp)

    blocks, sizes = [], []
    for trk in range(NTRACKS):
        secs = tracks[trk]
        if not secs:
            blocks.append(b'')
            sizes.append(0)
            continue
        hdr = bytearray(b'Track-Info\r\n' + b'\0' * 4)
        hdr += bytes([trk, 0, 0, 0, max(s.n for s in secs), len(secs), 0x4E, 0xE5])
        for s in secs:
            hdr += bytes([s.c, s.h, s.r, s.n, s.st1, s.st2]) + struct.pack('<H', len(s.data))
        assert len(hdr) <= 256
        body = bytes(hdr.ljust(256, b'\0')) + b''.join(s.data for s in secs)
        body = body.ljust((len(body) + 255) // 256 * 256, b'\0')
        blocks.append(body)
        sizes.append(len(body) // 256)

    disk = bytearray(b'EXTENDED CPC DSK File\r\nDisk-Info\r\n')
    disk += b'mkdsktest.py  '[:14]
    disk += bytes([NTRACKS, 1, 0, 0]) + bytes(sizes)
    disk = disk.ljust(256, b'\0')
    for b in blocks:
        disk += b
    open(out, 'wb').write(disk)
    print(f"{out} : {NTRACKS} pistes, {len(disk)} octets")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2])
