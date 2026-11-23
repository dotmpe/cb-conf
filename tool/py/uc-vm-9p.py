#!/usr/bin/env python3
"""9P2000 file server for uc-vm guests.

QEMU virtio-9p and diod speak 9P2000.L. Stock 9front mounts 9P2000.
One process serves every export. Tattach aname is the host directory.
"""

import argparse
import os
import socket
import stat
import struct
import sys
import threading

Tversion, Rversion = 100, 101
Tauth, Rauth = 102, 103
Tattach, Rattach = 104, 105
Rerror = 107
Tflush, Rflush = 108, 109
Twalk, Rwalk = 110, 111
Topen, Ropen = 112, 113
Tcreate, Rcreate = 114, 115
Tread, Rread = 116, 117
Twrite, Rwrite = 118, 119
Tclunk, Rclunk = 120, 121
Tremove, Rremove = 122, 123
Tstat, Rstat = 124, 125
Twstat, Rwstat = 126, 127

DMDIR = 0x80000000
QTDIR = 0x80
NOFID = 0xFFFFFFFF
NOTAG = 0xFFFF
OREAD, OWRITE, ORDWR, OEXEC = 0, 1, 2, 3
OTRUNC = 0x10


class ProtoError(Exception):
    pass


class Export:
    def __init__(self, root, readonly):
        self.root = root
        self.readonly = readonly


def p8(n):
    return struct.pack("<B", n & 0xFF)


def p16(n):
    return struct.pack("<H", n & 0xFFFF)


def p32(n):
    return struct.pack("<I", n & 0xFFFFFFFF)


def p64(n):
    return struct.pack("<Q", n & 0xFFFFFFFFFFFFFFFF)


def cstr(buf, off):
    if off + 2 > len(buf):
        raise ProtoError("short string")
    n = struct.unpack_from("<H", buf, off)[0]
    off += 2
    if off + n > len(buf):
        raise ProtoError("short string")
    return buf[off:off + n].decode("utf-8", "surrogateescape"), off + n


def pstr(text):
    raw = text.encode("utf-8", "surrogateescape")
    if len(raw) > 0xFFFF:
        raise ProtoError("string too long")
    return p16(len(raw)) + raw


class Server:
    def __init__(self, exports):
        self.exports = exports
        self.qid_lock = threading.Lock()
        self.qids = {}
        self.next_qid = 1

    def qid_path(self, real):
        with self.qid_lock:
            path = self.qids.get(real)
            if path is None:
                path = self.next_qid
                self.next_qid += 1
                self.qids[real] = path
            return path

    def serve(self, addr, port):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((addr, port))
        sock.listen(8)
        while True:
            conn, _peer = sock.accept()
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            threading.Thread(target=self.conn, args=(conn,), daemon=True).start()

    def conn(self, sock):
        fids = {}
        msize = 8192
        try:
            while True:
                hdr = read_exact(sock, 4)
                size = struct.unpack("<I", hdr)[0]
                if size < 7 or size > max(msize, 65536):
                    break
                msg = read_exact(sock, size - 4)
                typ = msg[0]
                tag = struct.unpack_from("<H", msg, 1)[0]
                body = msg[3:]
                try:
                    reply, msize = self.dispatch(fids, msize, typ, body)
                    send(sock, reply[0], tag, reply[1])
                except (ProtoError, IndexError, struct.error) as exc:
                    send(sock, Rerror, tag, pstr(str(exc) or "protocol error"))
        except (EOFError, ConnectionError, OSError):
            pass
        finally:
            for fid in list(fids.values()):
                fid.close()
            sock.close()

    def dispatch(self, fids, msize, typ, body):
        if typ == Tversion:
            their = struct.unpack_from("<I", body, 0)[0]
            version, _ = cstr(body, 4)
            msize = min(their, 65536)
            if msize < 256 or not version.startswith("9P2000"):
                return (Rversion, p32(msize) + pstr("unknown")), msize
            return (Rversion, p32(msize) + pstr("9P2000")), msize
        if typ == Tauth:
            raise ProtoError("authentication not required")
        if typ == Tflush:
            return (Rflush, b""), msize
        if typ == Tattach:
            return (Rattach, self.attach(fids, body)), msize
        if typ == Twalk:
            return (Rwalk, self.walk(fids, body)), msize
        if typ == Topen:
            return (Ropen, self.open(fids, msize, body)), msize
        if typ == Tcreate:
            return (Rcreate, self.create(fids, msize, body)), msize
        if typ == Tread:
            return (Rread, self.read(fids, msize, body)), msize
        if typ == Twrite:
            return (Rwrite, self.write(fids, body)), msize
        if typ == Tclunk:
            self.clunk(fids, body)
            return (Rclunk, b""), msize
        if typ == Tremove:
            self.remove(fids, body)
            return (Rremove, b""), msize
        if typ == Tstat:
            return (Rstat, self.stat(fids, body)), msize
        if typ == Twstat:
            raise ProtoError("wstat prohibited")
        raise ProtoError("unknown message %d" % typ)

    def export_for(self, aname):
        aname = aname.rstrip("/")
        matches = []
        for exp in self.exports:
            root = exp.root.rstrip("/")
            if aname in ("", root):
                matches.append(exp)
        if len(matches) == 1:
            return matches[0]
        if not aname:
            raise ProtoError("aname required")
        raise ProtoError("unknown export")

    def attach(self, fids, body):
        fid = struct.unpack_from("<I", body, 0)[0]
        uname, off = cstr(body, 8)
        aname, _off = cstr(body, off)
        del uname
        if fid == NOFID or fid in fids:
            raise ProtoError("fid in use")
        exp = self.export_for(aname)
        fids[fid] = Fid(self, exp, "")
        return self.qid(fids[fid].real())

    def walk(self, fids, body):
        fid = struct.unpack_from("<I", body, 0)[0]
        newfid = struct.unpack_from("<I", body, 4)[0]
        nwname = struct.unpack_from("<H", body, 8)[0]
        off = 10
        names = []
        for _ in range(nwname):
            name, off = cstr(body, off)
            names.append(name)
        src = self.fid(fids, fid)
        if src.opened is not None and newfid == fid and names:
            raise ProtoError("fid open")
        if newfid != fid and newfid in fids:
            raise ProtoError("fid in use")
        if not names:
            if newfid != fid:
                fids[newfid] = Fid(self, src.export, src.rel)
            return p16(0)
        rel = src.rel
        qids = b""
        nqid = 0
        for name in names:
            try:
                rel = self.step(src.export, rel, name)
            except ProtoError:
                if nqid == 0:
                    raise
                return p16(nqid) + qids
            qids += self.qid(self.locate(src.export, rel))
            nqid += 1
        fids[newfid] = Fid(self, src.export, rel)
        return p16(nqid) + qids

    def step(self, exp, rel, name):
        if name in ("",) or "/" in name or "\x00" in name:
            raise ProtoError("bad name")
        if name == ".":
            return rel
        if name == "..":
            return os.path.dirname(rel) if rel else ""
        nxt = name if not rel else rel + "/" + name
        self.locate(exp, nxt)
        return nxt

    def open(self, fids, msize, body):
        fidn = struct.unpack_from("<I", body, 0)[0]
        mode = body[4]
        fid = self.fid(fids, fidn)
        fid.open_at(mode)
        return self.qid(fid.real()) + p32(max(msize - 24, 0))

    def create(self, fids, msize, body):
        fidn = struct.unpack_from("<I", body, 0)[0]
        name, off = cstr(body, 4)
        perm = struct.unpack_from("<I", body, off)[0]
        mode = body[off + 4]
        fid = self.fid(fids, fidn)
        fid.create(name, perm, mode)
        return self.qid(fid.real()) + p32(max(msize - 24, 0))

    def read(self, fids, msize, body):
        fidn = struct.unpack_from("<I", body, 0)[0]
        offset = struct.unpack_from("<Q", body, 4)[0]
        count = struct.unpack_from("<I", body, 12)[0]
        count = min(count, max(msize - 11, 0))
        data = self.fid(fids, fidn).pread(offset, count)
        return p32(len(data)) + data

    def write(self, fids, body):
        fidn = struct.unpack_from("<I", body, 0)[0]
        offset = struct.unpack_from("<Q", body, 4)[0]
        count = struct.unpack_from("<I", body, 12)[0]
        data = body[16:16 + count]
        if len(data) != count:
            raise ProtoError("short write")
        n = self.fid(fids, fidn).pwrite(offset, data)
        return p32(n)

    def clunk(self, fids, body):
        fidn = struct.unpack_from("<I", body, 0)[0]
        fid = fids.pop(fidn, None)
        if fid is None:
            raise ProtoError("unknown fid")
        fid.close()

    def remove(self, fids, body):
        fidn = struct.unpack_from("<I", body, 0)[0]
        fid = fids.pop(fidn, None)
        if fid is None:
            raise ProtoError("unknown fid")
        try:
            fid.remove()
        finally:
            fid.close()

    def stat(self, fids, body):
        fidn = struct.unpack_from("<I", body, 0)[0]
        blob = self.fid(fids, fidn).stat()
        return p16(len(blob)) + blob

    def fid(self, fids, fidn):
        fid = fids.get(fidn)
        if fid is None:
            raise ProtoError("unknown fid")
        return fid

    def locate(self, exp, rel):
        root = exp.root
        path = root if not rel else os.path.realpath(os.path.join(root, rel))
        if path != root and not path.startswith(root + os.sep):
            raise ProtoError("path escapes export")
        if not os.path.exists(path):
            raise ProtoError("file does not exist")
        return path

    def qid(self, real):
        st = os.stat(real)
        qtype = QTDIR if stat.S_ISDIR(st.st_mode) else 0
        return p8(qtype) + p32(int(st.st_mtime)) + p64(self.qid_path(real))


class Fid:
    def __init__(self, server, export, rel):
        self.server = server
        self.export = export
        self.rel = rel
        self.opened = None
        self.fh = None
        self.dirimage = None

    def close(self):
        if self.fh is not None:
            os.close(self.fh)
            self.fh = None

    def real(self):
        return self.server.locate(self.export, self.rel)

    def open_at(self, mode):
        access = mode & 3
        trunc = bool(mode & OTRUNC)
        if self.export.readonly and (access in (OWRITE, ORDWR) or trunc):
            raise ProtoError("read only")
        path = self.real()
        if os.path.isdir(path):
            if access != OREAD or trunc:
                raise ProtoError("is a directory")
            self.dirimage = directory_image(self.server, self.export, path)
            self.opened = "dir"
            return
        flags = {OREAD: os.O_RDONLY, OWRITE: os.O_WRONLY, ORDWR: os.O_RDWR, OEXEC: os.O_RDONLY}[access]
        if trunc:
            flags |= os.O_TRUNC
        self.fh = os.open(path, flags)
        self.opened = "file"

    def create(self, name, perm, mode):
        if self.export.readonly:
            raise ProtoError("read only")
        if not name or name in (".", "..") or "/" in name or "\x00" in name:
            raise ProtoError("bad name")
        parent = self.real()
        if not os.path.isdir(parent):
            raise ProtoError("not a directory")
        dest = os.path.join(parent, name)
        if os.path.lexists(dest):
            raise ProtoError("file already exists")
        try:
            if perm & DMDIR:
                os.mkdir(dest, perm & 0o777)
            else:
                fd = os.open(dest, os.O_CREAT | os.O_EXCL | os.O_RDWR, perm & 0o777)
                os.close(fd)
        except OSError as exc:
            raise ProtoError(exc.strerror or "create failed") from exc
        self.rel = name if not self.rel else self.rel + "/" + name
        self.open_at(mode)

    def pread(self, offset, count):
        if self.opened == "dir":
            return slice_dir(self.dirimage, offset, count)
        if self.opened != "file":
            raise ProtoError("fid not open")
        try:
            return os.pread(self.fh, count, offset)
        except OSError as exc:
            raise ProtoError(exc.strerror or "read failed") from exc

    def pwrite(self, offset, data):
        if self.export.readonly:
            raise ProtoError("read only")
        if self.opened != "file":
            raise ProtoError("fid not open for write")
        try:
            return os.pwrite(self.fh, data, offset)
        except OSError as exc:
            raise ProtoError(exc.strerror or "write failed") from exc

    def remove(self):
        if self.export.readonly:
            raise ProtoError("read only")
        path = self.real()
        try:
            if os.path.isdir(path):
                os.rmdir(path)
            else:
                os.remove(path)
        except OSError as exc:
            raise ProtoError(exc.strerror or "remove failed") from exc

    def stat(self):
        path = self.real()
        name = "/" if not self.rel else os.path.basename(self.rel)
        return pack_stat(self.server, self.export, path, name)


def pack_stat(server, export, path, name):
    st = os.stat(path)
    mode = stat.S_IMODE(st.st_mode)
    qtype = 0
    if stat.S_ISDIR(st.st_mode):
        mode |= DMDIR
        qtype = QTDIR
    if export.readonly:
        mode &= ~0o222
    user = "none"
    try:
        import pwd
        user = pwd.getpwuid(os.getuid()).pw_name
    except (ImportError, KeyError):
        pass
    tail = (
        p16(0) + p32(0)
        + p8(qtype) + p32(int(st.st_mtime)) + p64(server.qid_path(path))
        + p32(mode) + p32(int(st.st_atime)) + p32(int(st.st_mtime))
        + p64(0 if stat.S_ISDIR(st.st_mode) else st.st_size)
        + pstr(name) + pstr(user) + pstr(user) + pstr(user)
    )
    return p16(len(tail)) + tail


def directory_image(server, export, path):
    parts = []
    try:
        names = sorted(os.listdir(path))
    except OSError as exc:
        raise ProtoError(exc.strerror or "listdir failed") from exc
    for name in names:
        child = os.path.join(path, name)
        try:
            real = os.path.realpath(child)
        except OSError:
            continue
        root = export.root
        if real != root and not real.startswith(root + os.sep):
            continue
        if not os.path.exists(real):
            continue
        parts.append(pack_stat(server, export, real, name))
    return b"".join(parts)


def slice_dir(image, offset, count):
    if offset > len(image):
        return b""
    if offset < len(image) and not dir_boundary(image, offset):
        raise ProtoError("bad directory offset")
    end = min(len(image), offset + count)
    pos = offset
    while pos + 2 <= len(image):
        size = struct.unpack_from("<H", image, pos)[0]
        nxt = pos + 2 + size
        if nxt > end:
            break
        pos = nxt
    return image[offset:pos]


def dir_boundary(image, offset):
    pos = 0
    while pos < offset and pos + 2 <= len(image):
        size = struct.unpack_from("<H", image, pos)[0]
        pos += 2 + size
    return pos == offset


def read_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise EOFError
        buf += chunk
    return buf


def send(sock, typ, tag, payload):
    body = p8(typ) + p16(tag) + payload
    sock.sendall(p32(4 + len(body)) + body)


def load_exports(path):
    exports = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            mode, root = line.split("\t", 1)
            if mode not in ("ro", "rw"):
                sys.exit("bad export mode: %s" % mode)
            real = os.path.realpath(root)
            if not os.path.isdir(real):
                sys.exit("export is not a directory: %s" % real)
            exports.append(Export(real, mode == "ro"))
    if not exports:
        sys.exit("no exports")
    return exports


def main():
    parser = argparse.ArgumentParser(description="uc-vm 9P2000 server")
    parser.add_argument("--addr", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--exports", required=True)
    args = parser.parse_args()
    exports = load_exports(args.exports)
    Server(exports).serve(args.addr, args.port)


if __name__ == "__main__":
    main()
