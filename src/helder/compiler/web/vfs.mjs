// helder.compiler.web's file system: a tree in memory that helder's compiler
// reads and writes through WASI preview 1 (Wasi, below) and TypeScript's API
// through its file system callbacks (Vfs.typescript), the page through the
// worker's write and read. Directories persisted (/cache) are mirrored to
// OPFS: read back at start (Vfs.restore), written after each build
// (Vfs.persist: the files changed since).
//
// A file's time is the write's, in milliseconds, and never the same as the
// last write's: the compilation server and tsgo's snapshots compare times.

const encoder = new TextEncoder();
const decoder = new TextDecoder();
let clock = 0;
const stamp = () => (clock = Math.max(Date.now(), clock + 1));
let inodes = 1;

export class Node {
	constructor(dir) {
		this.dir = dir ? new Map() : null;
		this.data = dir ? null : new Uint8Array(0);
		this.size = 0;
		this.mtime = stamp();
		this.ino = inodes++;
	}

	bytes() {
		return this.data.subarray(0, this.size);
	}

	// room for n bytes
	reserve(n) {
		if (n <= this.data.length) return;
		const d = new Uint8Array(Math.max(n, this.data.length * 2, 256));
		d.set(this.data.subarray(0, this.size));
		this.data = d;
		this.shared = false;
	}
}

const parts = (path) => path.split('/').filter((p) => p !== '' && p !== '.');

export class Vfs {
	constructor() {
		this.root = new Node(true);
		// the paths under a persisted directory written since the last persist
		this.persisted = [];
		this.dirty = new Set();
	}

	// the node at an absolute path (.. resolved), or null
	lookup(path) {
		const stack = [this.root];
		for (const p of parts(path)) {
			const cur = stack[stack.length - 1];
			if (p === '..') {
				if (stack.length > 1) stack.pop();
				continue;
			}
			const next = cur.dir?.get(p);
			if (!next) return null;
			stack.push(next);
		}
		return stack[stack.length - 1];
	}

	mkdirs(path) {
		let n = this.root;
		for (const p of parts(path)) {
			let next = n.dir.get(p);
			if (!next) n.dir.set(p, (next = new Node(true)));
			if (!next.dir) throw new Error(path + ': not a directory');
			n = next;
		}
		return n;
	}

	// a file written (string: UTF-8), with the directories it needs
	writeFile(path, content) {
		const bytes = typeof content === 'string' ? encoder.encode(content) : content;
		const ps = parts(path), name = ps.pop();
		const dir = this.mkdirs(ps.join('/'));
		const n = new Node(false);
		n.data = bytes;
		n.size = bytes.length;
		dir.dir.set(name, n);
		this.touched(path);
		return n;
	}

	readFile(path) {
		const n = this.lookup(path);
		return n && !n.dir ? n.bytes() : null;
	}

	readText(path) {
		const b = this.readFile(path);
		return b === null ? null : decoder.decode(b);
	}

	remove(path) {
		const ps = parts(path), name = ps.pop();
		const dir = this.lookup('/' + ps.join('/'));
		if (dir?.dir?.delete(name)) this.touched(path);
	}

	// every file under dir (absolute paths)
	list(dir) {
		const out = [];
		const walk = (n, p) => {
			for (const [k, c] of n.dir) c.dir ? walk(c, p + '/' + k) : out.push(p + '/' + k);
		};
		const n = this.lookup(dir);
		if (n?.dir) walk(n, dir === '/' ? '' : dir.replace(/\/$/, ''));
		return out.sort();
	}

	stats() {
		let files = 0, bytes = 0;
		const walk = (n) => {
			for (const c of n.dir.values()) c.dir ? walk(c) : (files++, (bytes += c.size));
		};
		walk(this.root);
		return { files, bytes };
	}

	touched(path) {
		for (const p of this.persisted) if (path.startsWith(p + '/')) this.dirty.add(path);
	}

	// a bundle's files under at: a little-endian u32 n, n bytes of UTF-8 JSON
	// [[path, size], ...], then the files' bytes in that order (bundle.mjs)
	unbundle(bytes, at = '/') {
		const n = new DataView(bytes.buffer, bytes.byteOffset).getUint32(0, true);
		const index = JSON.parse(decoder.decode(bytes.subarray(4, 4 + n)));
		let p = 4 + n;
		for (const [path, size] of index) {
			// (a view of the bundle: no copy; a write replaces the node's data)
			this.writeFile(at.replace(/\/$/, '') + '/' + path, bytes.subarray(p, p + size)).shared = true;
			p += size;
		}
		return index.length;
	}

	// OPFS: the directory dir mirrored under OPFS's name (false: no OPFS here)
	async restore(dir, name = 'helder-compiler') {
		this.persisted.push(dir);
		if (!globalThis.navigator?.storage?.getDirectory) return false;
		let top;
		try {
			top = await (await navigator.storage.getDirectory()).getDirectoryHandle(name, { create: true });
		} catch {
			return false;
		}
		this.opfs = top;
		const read = async (h, p) => {
			for await (const [k, c] of h.entries()) {
				if (c.kind === 'directory') await read(c, p + '/' + k);
				else this.writeFile(p + '/' + k, new Uint8Array(await (await c.getFile()).arrayBuffer()));
			}
		};
		await read(top, dir);
		this.dirty.clear();
		return true;
	}

	// the files written or removed under the persisted directories since, to OPFS
	async persist() {
		if (!this.opfs || this.dirty.size === 0) return 0;
		const paths = [...this.dirty];
		this.dirty.clear();
		let n = 0;
		for (const path of paths) {
			const base = this.persisted.find((d) => path.startsWith(d + '/'));
			const ps = path.slice(base.length + 1).split('/'), name = ps.pop();
			try {
				let h = this.opfs;
				for (const p of ps) h = await h.getDirectoryHandle(p, { create: true });
				const data = this.readFile(path);
				if (data === null) await h.removeEntry(name).catch(() => {});
				else {
					const w = await (await h.getFileHandle(name, { create: true })).createWritable();
					await w.write(data);
					await w.close();
				}
				n++;
			} catch {}
		}
		return n;
	}

	// TypeScript's API's file system callbacks (typescript/wasm's fs option);
	// its own library files (bundled:///libs/...) read from libs
	typescript(libs) {
		const at = (p) => this.lookup(p.startsWith('bundled:///libs/') ? libs + '/' + p.slice(16) : p);
		return {
			readFile: (p) => {
				const n = at(p);
				return n && !n.dir ? decoder.decode(n.bytes()) : undefined;
			},
			fileExists: (p) => {
				const n = at(p);
				return !!n && !n.dir;
			},
			directoryExists: (p) => !!at(p)?.dir,
			getAccessibleEntries: (p) => {
				const n = at(p), files = [], directories = [];
				if (n?.dir) for (const [k, c] of n.dir) (c.dir ? directories : files).push(k);
				return { files: files.sort(), directories: directories.sort() };
			},
			realpath: (p) => p,
			stat: (p) => {
				const n = at(p);
				return n ? { mode: n.dir ? 0o40755 : 0o100644, size: n.dir ? 0 : n.size, mtime: new Date(n.mtime) } : undefined;
			},
			writeFile: (p, data) => {
				this.writeFile(p, data);
			},
			removeFile: (p) => {
				this.remove(p);
			},
		};
	}
}

/** proc_exit: the end of the program, thrown through its frames */
export class Exit {
	constructor(code) {
		this.code = code;
	}
}

// errno (WASI preview 1)
const ESUCCESS = 0, EBADF = 8, EEXIST = 20, EINVAL = 28, EISDIR = 31, ENOENT = 44, ENOSYS = 52, ENOTDIR = 54, ENOTEMPTY = 55;
const DIRECTORY = 3, REGULAR_FILE = 4;

// WASI preview 1 over a Vfs: "/" the one preopened directory (fd 3), stdout
// and stderr to out(fd, bytes), the clocks, random bytes, poll_oneoff's
// clocks (a worker may block: it waits). What a compiler does not reach
// (sockets, processes) fails with ENOSYS.
export class Wasi {
	constructor(vfs, { args = [], env = {}, out = () => {} } = {}) {
		this.vfs = vfs;
		this.args = args;
		this.env = Object.entries(env).map(([k, v]) => `${k}=${v}`);
		this.out = out;
		this.fds = new Map([[3, { node: vfs.root, path: '/', pos: 0 }]]);
		this.next = 4;
		this.memory = null;
	}

	view() {
		return new DataView(this.memory.buffer);
	}

	str(p, n) {
		return decoder.decode(new Uint8Array(this.memory.buffer, p, n));
	}

	u64(at, v) {
		const dv = this.view();
		dv.setUint32(at, v % 4294967296 >>> 0, true);
		dv.setUint32(at + 4, Math.floor(v / 4294967296) >>> 0, true);
	}

	sizes(list, n, size) {
		const dv = this.view();
		dv.setUint32(n, list.length, true);
		dv.setUint32(size, list.reduce((t, s) => t + encoder.encode(s).length + 1, 0), true);
		return ESUCCESS;
	}

	strings(list, p, buf) {
		const mem = new Uint8Array(this.memory.buffer), dv = this.view();
		list.forEach((s, k) => {
			const b = encoder.encode(s);
			dv.setUint32(p + 4 * k, buf, true);
			mem.set(b, buf);
			mem[buf + b.length] = 0;
			buf += b.length + 1;
		});
		return ESUCCESS;
	}

	now(id) {
		return id === 0 ? Date.now() * 1e6 : performance.now() * 1e6;
	}

	// a path relative to a directory's fd: its node (null: none), its parent and name
	resolve(fd, p, n) {
		const o = this.fds.get(fd);
		if (!o) return { node: null, parent: null, name: '', err: EBADF };
		const path = this.str(p, n);
		const full = path.startsWith('/') ? path : (o.path === '/' ? '' : o.path) + '/' + path;
		const ps = [];
		for (const s of full.split('/')) if (s === '..') ps.pop(); else if (s !== '' && s !== '.') ps.push(s);
		const name = ps.pop() ?? '';
		const parent = this.vfs.lookup('/' + ps.join('/'));
		if (name === '') return { node: parent, parent: null, name: '', path: '/' + ps.join('/'), err: parent ? ESUCCESS : ENOENT };
		if (!parent) return { node: null, parent: null, name, err: ENOENT };
		if (!parent.dir) return { node: null, parent: null, name, err: ENOTDIR };
		const node = parent.dir.get(name) ?? null;
		return { node, parent, name, path: '/' + [...ps, name].join('/'), err: node ? ESUCCESS : ENOENT };
	}

	stat(node, buf) {
		const dv = this.view();
		new Uint8Array(this.memory.buffer, buf, 64).fill(0);
		this.u64(buf + 8, node.ino);
		dv.setUint8(buf + 16, node.dir ? DIRECTORY : REGULAR_FILE);
		this.u64(buf + 24, 1);
		this.u64(buf + 32, node.dir ? 0 : node.size);
		for (const t of [40, 48, 56]) this.u64(buf + t, node.mtime * 1e6);
		return ESUCCESS;
	}

	imports() {
		const w = this;
		return {
			wasi_snapshot_preview1: {
				args_sizes_get: (n, size) => w.sizes(w.args, n, size),
				args_get: (p, buf) => w.strings(w.args, p, buf),
				environ_sizes_get: (n, size) => w.sizes(w.env, n, size),
				environ_get: (p, buf) => w.strings(w.env, p, buf),
				clock_time_get: (id, _precision, at) => {
					if (id < 0 || id > 3) return EINVAL;
					w.u64(at, Math.floor(w.now(id)));
					return ESUCCESS;
				},
				clock_res_get: (_id, at) => (w.u64(at, 1000), ESUCCESS),
				fd_write: (fd, iovs, n, done) => w.rw(true, fd, iovs, n, done),
				fd_read: (fd, iovs, n, done) => w.rw(false, fd, iovs, n, done),
				fd_pwrite: () => ENOSYS,
				fd_pread: () => ENOSYS,
				fd_close: (fd) => {
					if (fd <= 3) return ESUCCESS;
					return w.fds.delete(fd) ? ESUCCESS : EBADF;
				},
				fd_seek: (fd, offset, whence, at) => {
					const o = w.fds.get(fd);
					if (!o || o.node.dir) return EBADF;
					const base = whence === 0 ? 0 : whence === 1 ? o.pos : whence === 2 ? o.node.size : NaN;
					const pos = base + Number(offset);
					if (!(pos >= 0)) return EINVAL;
					o.pos = pos;
					w.u64(at, pos);
					return ESUCCESS;
				},
				fd_tell: (fd, at) => {
					const o = w.fds.get(fd);
					if (!o) return EBADF;
					w.u64(at, o.pos);
					return ESUCCESS;
				},
				fd_sync: () => ESUCCESS,
				fd_datasync: () => ESUCCESS,
				fd_filestat_get: (fd, buf) => {
					const o = w.fds.get(fd);
					return o ? w.stat(o.node, buf) : EBADF;
				},
				fd_filestat_set_size: (fd, size) => {
					const o = w.fds.get(fd);
					if (!o || o.node.dir) return EBADF;
					const n = Number(size);
					o.node.reserve(n);
					if (n > o.node.size) o.node.data.fill(0, o.node.size, n);
					o.node.size = n;
					o.node.mtime = stamp();
					w.vfs.touched(o.path);
					return ESUCCESS;
				},
				fd_filestat_set_times: () => ESUCCESS,
				path_filestat_set_times: () => ESUCCESS,
				fd_fdstat_get: (fd, buf) => {
					const o = w.fds.get(fd);
					if (!o && fd > 2) return EBADF;
					const dv = w.view();
					new Uint8Array(w.memory.buffer, buf, 24).fill(0);
					dv.setUint8(buf, !o ? 2 : o.node.dir ? DIRECTORY : REGULAR_FILE);
					for (let k = 0; k < 4; k++) dv.setUint32(buf + 8 + 4 * k, 0xffffffff, true);
					return ESUCCESS;
				},
				fd_fdstat_set_flags: () => ESUCCESS,
				fd_prestat_get: (fd, buf) => {
					if (fd !== 3) return EBADF;
					w.view().setUint8(buf, 0);
					w.view().setUint32(buf + 4, 1, true);
					return ESUCCESS;
				},
				fd_prestat_dir_name: (fd, p, n) => {
					if (fd !== 3) return EBADF;
					if (n >= 1) w.view().setUint8(p, 47);
					return ESUCCESS;
				},
				fd_readdir: (fd, buf, len, cookie, used) => w.readdir(fd, buf, len, cookie, used),
				fd_renumber: () => ENOSYS,
				path_open: (fd, _dirflags, p, n, oflags, _rb, _ri, fdflags, at) => {
					const r = w.resolve(fd, p, n);
					let node = r.node;
					// oflags: CREAT 1, DIRECTORY 2, EXCL 4, TRUNC 8; fdflags: APPEND 1
					if (!node) {
						if (!(oflags & 1) || !r.parent) return r.err;
						node = new Node(false);
						r.parent.dir.set(r.name, node);
						w.vfs.touched(r.path);
					} else if (oflags & 4) return EEXIST;
					if (oflags & 2 && !node.dir) return ENOTDIR;
					if (oflags & 8) {
						if (node.dir) return EISDIR;
						// (a bundle's view is not written in place)
						node.data = new Uint8Array(0);
						node.size = 0;
						node.mtime = stamp();
						w.vfs.touched(r.path);
					}
					const id = w.next++;
					w.fds.set(id, { node, path: r.path, pos: 0, append: !!(fdflags & 1) });
					w.view().setUint32(at, id, true);
					return ESUCCESS;
				},
				path_filestat_get: (fd, _flags, p, n, buf) => {
					const r = w.resolve(fd, p, n);
					return r.node ? w.stat(r.node, buf) : r.err;
				},
				path_create_directory: (fd, p, n) => {
					const r = w.resolve(fd, p, n);
					if (r.node) return EEXIST;
					if (!r.parent) return r.err;
					r.parent.dir.set(r.name, new Node(true));
					return ESUCCESS;
				},
				path_remove_directory: (fd, p, n) => {
					const r = w.resolve(fd, p, n);
					if (!r.node) return r.err;
					if (!r.node.dir) return ENOTDIR;
					if (r.node.dir.size) return ENOTEMPTY;
					r.parent.dir.delete(r.name);
					return ESUCCESS;
				},
				path_unlink_file: (fd, p, n) => {
					const r = w.resolve(fd, p, n);
					if (!r.node) return r.err;
					if (r.node.dir) return EISDIR;
					r.parent.dir.delete(r.name);
					w.vfs.touched(r.path);
					return ESUCCESS;
				},
				path_rename: (fd, p, n, fd2, p2, n2) => {
					const a = w.resolve(fd, p, n), b = w.resolve(fd2, p2, n2);
					if (!a.node) return a.err;
					if (!b.parent) return b.err;
					if (b.node?.dir?.size) return ENOTEMPTY;
					a.parent.dir.delete(a.name);
					b.parent.dir.set(b.name, a.node);
					w.vfs.touched(a.path);
					if (a.node.dir) for (const f of w.vfs.list(b.path)) w.vfs.touched(f);
					else w.vfs.touched(b.path);
					return ESUCCESS;
				},
				path_symlink: () => ENOSYS,
				path_readlink: () => EINVAL,
				path_link: () => ENOSYS,
				poll_oneoff: (subs, events, n, nevents) => {
					const dv = w.view();
					for (let k = 0; k < n; k++) {
						const s = subs + 48 * k;
						if (dv.getUint8(s + 8) !== 0) return ENOSYS;
						const id = dv.getUint32(s + 16, true);
						const timeout = dv.getUint32(s + 24, true) + dv.getUint32(s + 28, true) * 4294967296;
						const end = dv.getUint16(s + 40, true) & 1 ? timeout : w.now(id) + timeout;
						while (w.now(id) < end) {}
						const e = events + 32 * k;
						new Uint8Array(w.memory.buffer, e, 32).fill(0);
						dv.setUint32(e, dv.getUint32(s, true), true);
						dv.setUint32(e + 4, dv.getUint32(s + 4, true), true);
					}
					dv.setUint32(nevents, n, true);
					return ESUCCESS;
				},
				random_get: (p, n) => {
					for (let at = 0; at < n; at += 65536) crypto.getRandomValues(new Uint8Array(w.memory.buffer, p + at, Math.min(65536, n - at)));
					return ESUCCESS;
				},
				sched_yield: () => ESUCCESS,
				proc_raise: () => ENOSYS,
				proc_exit: (code) => {
					throw new Exit(code);
				},
				sock_accept: () => ENOSYS,
				sock_recv: () => ENOSYS,
				sock_send: () => ENOSYS,
				sock_shutdown: () => ENOSYS,
			},
		};
	}

	rw(write, fd, iovs, n, done) {
		const dv = this.view();
		const o = this.fds.get(fd);
		if (!o && fd > 2) return EBADF;
		if (o?.node.dir) return EISDIR;
		let total = 0;
		for (let k = 0; k < n; k++) {
			const p = dv.getUint32(iovs + 8 * k, true), len = dv.getUint32(iovs + 8 * k + 4, true);
			if (write) {
				const b = new Uint8Array(this.memory.buffer, p, len);
				if (fd === 1 || fd === 2) this.out(fd, b.slice());
				else if (fd === 0) return EBADF;
				else {
					const node = o.node;
					if (o.append) o.pos = node.size;
					// (a bundle's view: copied before a write in place)
					if (node.shared) {
						node.data = node.data.slice(0, node.size);
						node.shared = false;
					}
					node.reserve(o.pos + len);
					node.data.set(b, o.pos);
					o.pos += len;
					if (o.pos > node.size) node.size = o.pos;
					node.mtime = stamp();
					this.vfs.touched(o.path);
				}
				total += len;
			} else {
				if (fd <= 2) break;
				const m = Math.max(0, Math.min(len, o.node.size - o.pos));
				new Uint8Array(this.memory.buffer, p, m).set(o.node.data.subarray(o.pos, o.pos + m));
				o.pos += m;
				total += m;
				if (m < len) break;
			}
		}
		this.view().setUint32(done, total, true);
		return ESUCCESS;
	}

	// ".", ".." and the names in order, from the cookie's index
	readdir(fd, buf, len, cookie, used) {
		const o = this.fds.get(fd);
		if (!o) return EBADF;
		if (!o.node.dir) return ENOTDIR;
		if (!o.entries || Number(cookie) === 0) o.entries = ['.', '..', ...[...o.node.dir.keys()].sort()];
		const mem = new Uint8Array(this.memory.buffer);
		let at = 0, k = Number(cookie);
		while (k < o.entries.length && at < len) {
			const name = encoder.encode(o.entries[k]);
			const child = k < 2 ? o.node : o.node.dir.get(o.entries[k]);
			const e = new Uint8Array(24 + name.length), ev = new DataView(e.buffer);
			ev.setUint32(0, k + 1, true);
			ev.setUint32(8, child?.ino ?? 0, true);
			ev.setUint32(16, name.length, true);
			ev.setUint8(20, child?.dir ? DIRECTORY : REGULAR_FILE);
			e.set(name, 24);
			const m = Math.min(e.length, len - at);
			mem.set(e.subarray(0, m), buf + at);
			at += m;
			k++;
		}
		this.view().setUint32(used, at, true);
		return ESUCCESS;
	}
}
