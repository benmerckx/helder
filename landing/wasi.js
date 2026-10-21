// WASI preview 1 over a file system in memory: what the compiler (haxe.wasm,
// @hxmc/wasm) needs to run in a browser's worker (compiler.js), and in node
// for the checks (test.mjs). One directory tree (MemFS) preopened as "/";
// relative paths resolve against it (the compiler is given PWD=/).
//
//   const fs = new MemFS();
//   fs.mount('/std', pack);                    // files from a pack (unpack)
//   const w = wasi({args, env, fs, stdout, stderr, onOpen});
//   const inst = await WebAssembly.instantiate(module, {wasi_snapshot_preview1: w.imports});
//   const code = w.start(inst);                // _start; the exit code
//
// onOpen(path, writing) is told of every file opened (the loader's
// particles: sources read, objects written).

// a pack: a little-endian u32 n, n bytes of JSON [[path, size], ...], then the
// files' bytes in that order (build.mjs writes them)
export function unpack(bytes) {
	const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
	const n = new DataView(b.buffer, b.byteOffset).getUint32(0, true);
	const index = JSON.parse(new TextDecoder().decode(b.subarray(4, 4 + n)));
	const files = [];
	let at = 4 + n;
	for (const [path, size] of index) {
		files.push([path, b.subarray(at, at + size)]);
		at += size;
	}
	return files;
}

let inodes = 1;
class Dir {
	constructor() {
		this.entries = new Map();
		this.ino = inodes++;
		this.mtime = BigInt(Date.now()) * 1000000n;
	}
}
class File {
	constructor(data = new Uint8Array(0)) {
		this.data = data;
		this.size = data.length;
		this.ino = inodes++;
		this.mtime = BigInt(Date.now()) * 1000000n;
	}
	bytes() {
		return this.data.subarray(0, this.size);
	}
	reserve(n) {
		if (n <= this.data.length) return;
		const d = new Uint8Array(Math.max(n, this.data.length * 2, 4096));
		d.set(this.bytes());
		this.data = d;
	}
}

export class MemFS {
	constructor() {
		this.root = new Dir();
	}
	// the node at an absolute or root-relative path, or null
	lookup(path) {
		let n = this.root;
		for (const part of split(path)) {
			if (!(n instanceof Dir)) return null;
			n = n.entries.get(part);
			if (!n) return null;
		}
		return n;
	}
	mkdirs(path) {
		let n = this.root;
		for (const part of split(path)) {
			let c = n.entries.get(part);
			if (!c) n.entries.set(part, (c = new Dir()));
			if (!(c instanceof Dir)) throw new Error(`${path}: not a directory`);
			n = c;
		}
		return n;
	}
	write(path, data) {
		const parts = split(path);
		const name = parts.pop();
		this.mkdirs(parts.join('/')).entries.set(name, new File(data));
	}
	read(path) {
		const n = this.lookup(path);
		return n instanceof File ? n.bytes() : null;
	}
	remove(path) {
		const parts = split(path);
		const name = parts.pop();
		const d = this.lookup(parts.join('/'));
		if (d instanceof Dir) d.entries.delete(name);
	}
	mount(at, files) {
		for (const [path, data] of files) this.write(`${at}/${path}`, data);
	}
}

// the parts of a path, "." dropped and ".." applied
function split(path) {
	const out = [];
	for (const p of path.split('/')) {
		if (p === '' || p === '.') continue;
		if (p === '..') out.pop();
		else out.push(p);
	}
	return out;
}

const E = { SUCCESS: 0, BADF: 8, EXIST: 20, INVAL: 28, ISDIR: 31, NOENT: 44, NOSYS: 52, NOTDIR: 54, NOTEMPTY: 55 };
const FILETYPE = { CHAR: 2, DIR: 3, FILE: 4 };

export class Exit {
	constructor(code) {
		this.code = code;
	}
}

export function wasi({ args = [], env = {}, fs, stdout = () => {}, stderr = () => {}, onOpen = () => {} }) {
	let memory = null;
	const enc = new TextEncoder();
	const dec = new TextDecoder();
	const view = () => new DataView(memory.buffer);
	const u8 = () => new Uint8Array(memory.buffer);
	const str = (p, n) => dec.decode(u8().subarray(p, p + n));
	// fds: 0-2 the streams, 3 the preopened root; {node, path, pos, append}
	const fds = [null, null, null, { node: fs.root, path: '/', pos: 0 }];
	const sinks = { 1: { out: stdout, dec: new TextDecoder(), text: '' }, 2: { out: stderr, dec: new TextDecoder(), text: '' } };
	const argv = args.map((a) => enc.encode(a + '\0'));
	const envv = Object.entries(env).map(([k, v]) => enc.encode(`${k}=${v}\0`));

	function flush(fd, end = false) {
		const s = sinks[fd];
		const lines = s.text.split('\n');
		s.text = end ? '' : lines.pop();
		for (const l of lines) if (l !== '' || !end) s.out(l);
	}
	function strings(list, ptrs, buf) {
		const v = view();
		for (const s of list) {
			v.setUint32(ptrs, buf, true);
			ptrs += 4;
			u8().set(s, buf);
			buf += s.length;
		}
		return E.SUCCESS;
	}
	function sizes(list, countPtr, sizePtr) {
		const v = view();
		v.setUint32(countPtr, list.length, true);
		v.setUint32(sizePtr, list.reduce((n, s) => n + s.length, 0), true);
		return E.SUCCESS;
	}
	// a path given relative to a directory fd: [parent dir, name, full path]
	function resolve(dirfd, p, n) {
		const d = fds[dirfd];
		if (!d || !(d.node instanceof Dir)) return null;
		let rel = str(p, n);
		const full = rel.startsWith('/') ? rel : `${d.path}/${rel}`;
		const parts = split(full);
		const name = parts.pop();
		const parent = fs.lookup(parts.join('/'));
		return { parent: parent instanceof Dir ? parent : null, name, full: '/' + parts.concat(name ?? []).join('/') };
	}
	function filestat(node, ptr) {
		const v = view();
		v.setBigUint64(ptr, 0n, true);
		v.setBigUint64(ptr + 8, BigInt(node ? node.ino : 0), true);
		v.setUint8(ptr + 16, node instanceof Dir ? FILETYPE.DIR : node ? FILETYPE.FILE : FILETYPE.CHAR);
		v.setBigUint64(ptr + 24, 1n, true);
		v.setBigUint64(ptr + 32, BigInt(node instanceof File ? node.size : 0), true);
		const t = node ? node.mtime : 0n;
		v.setBigUint64(ptr + 40, t, true);
		v.setBigUint64(ptr + 48, t, true);
		v.setBigUint64(ptr + 56, t, true);
		return E.SUCCESS;
	}
	function free() {
		for (let i = 4; ; i++) if (!fds[i]) return i;
	}

	const imports = {
		args_get: (ptrs, buf) => strings(argv, ptrs, buf),
		args_sizes_get: (c, s) => sizes(argv, c, s),
		environ_get: (ptrs, buf) => strings(envv, ptrs, buf),
		environ_sizes_get: (c, s) => sizes(envv, c, s),
		clock_time_get(id, _precision, ptr) {
			const ns = id === 0 ? BigInt(Date.now()) * 1000000n : BigInt(Math.round(performance.now() * 1e6));
			view().setBigUint64(ptr, ns, true);
			return E.SUCCESS;
		},
		clock_res_get(_id, ptr) {
			view().setBigUint64(ptr, 1000n, true);
			return E.SUCCESS;
		},
		random_get(p, n) {
			crypto.getRandomValues(u8().subarray(p, p + n));
			return E.SUCCESS;
		},
		fd_close(fd) {
			if (fd <= 3 || !fds[fd]) return E.BADF;
			fds[fd] = null;
			return E.SUCCESS;
		},
		fd_fdstat_get(fd, ptr) {
			const f = fds[fd];
			if (fd > 2 && !f) return E.BADF;
			const v = view();
			v.setUint8(ptr, fd <= 2 ? FILETYPE.CHAR : f.node instanceof Dir ? FILETYPE.DIR : FILETYPE.FILE);
			v.setUint16(ptr + 2, f?.append ? 1 : 0, true);
			v.setBigUint64(ptr + 8, 0xffffffffn, true);
			v.setBigUint64(ptr + 16, 0xffffffffn, true);
			return E.SUCCESS;
		},
		fd_fdstat_set_flags: () => E.SUCCESS,
		fd_filestat_get(fd, ptr) {
			if (fd <= 2) return filestat(null, ptr);
			const f = fds[fd];
			return f ? filestat(f.node, ptr) : E.BADF;
		},
		fd_prestat_get(fd, ptr) {
			if (fd !== 3) return E.BADF;
			const v = view();
			v.setUint8(ptr, 0);
			v.setUint32(ptr + 4, 1, true);
			return E.SUCCESS;
		},
		fd_prestat_dir_name(fd, p, n) {
			if (fd !== 3) return E.BADF;
			u8().set(enc.encode('/').subarray(0, n), p);
			return E.SUCCESS;
		},
		fd_read(fd, iovs, n, nread) {
			const f = fds[fd];
			if (fd === 0) {
				view().setUint32(nread, 0, true);
				return E.SUCCESS;
			}
			if (!f || !(f.node instanceof File)) return f ? E.ISDIR : E.BADF;
			const v = view(), m = u8(), data = f.node.bytes();
			let total = 0;
			for (let i = 0; i < n; i++) {
				const p = v.getUint32(iovs + i * 8, true), len = v.getUint32(iovs + i * 8 + 4, true);
				const chunk = data.subarray(f.pos, f.pos + len);
				m.set(chunk, p);
				f.pos += chunk.length;
				total += chunk.length;
				if (chunk.length < len) break;
			}
			v.setUint32(nread, total, true);
			return E.SUCCESS;
		},
		fd_pread: () => E.NOSYS,
		fd_pwrite: () => E.NOSYS,
		fd_write(fd, iovs, n, nwritten) {
			const v = view(), m = u8();
			let total = 0;
			const f = fds[fd];
			if (fd > 2 && (!f || !(f.node instanceof File))) return E.BADF;
			for (let i = 0; i < n; i++) {
				const p = v.getUint32(iovs + i * 8, true), len = v.getUint32(iovs + i * 8 + 4, true);
				const chunk = m.subarray(p, p + len);
				if (fd === 1 || fd === 2) {
					const s = sinks[fd];
					s.text += s.dec.decode(chunk, { stream: true });
					flush(fd);
				} else {
					const file = f.node;
					if (f.append) f.pos = file.size;
					file.reserve(f.pos + len);
					file.data.set(chunk, f.pos);
					f.pos += len;
					if (f.pos > file.size) file.size = f.pos;
				}
				total += len;
			}
			if (f?.node instanceof File) f.node.mtime = BigInt(Date.now()) * 1000000n;
			v.setUint32(nwritten, total, true);
			return E.SUCCESS;
		},
		fd_seek(fd, offset, whence, ptr) {
			const f = fds[fd];
			if (!f || !(f.node instanceof File)) return E.BADF;
			const base = whence === 0 ? 0 : whence === 1 ? f.pos : f.node.size;
			const pos = base + Number(offset);
			if (pos < 0) return E.INVAL;
			f.pos = pos;
			view().setBigUint64(ptr, BigInt(pos), true);
			return E.SUCCESS;
		},
		fd_tell(fd, ptr) {
			const f = fds[fd];
			if (!f) return E.BADF;
			view().setBigUint64(ptr, BigInt(f.pos), true);
			return E.SUCCESS;
		},
		fd_sync: () => E.SUCCESS,
		fd_datasync: () => E.SUCCESS,
		fd_readdir(fd, buf, len, cookie, used) {
			const f = fds[fd];
			if (!f || !(f.node instanceof Dir)) return E.NOTDIR;
			const v = view(), m = u8();
			const names = [...f.node.entries.keys()];
			let at = buf;
			const end = buf + len;
			for (let i = Number(cookie); i < names.length && at < end; i++) {
				const name = enc.encode(names[i]);
				const node = f.node.entries.get(names[i]);
				const head = new Uint8Array(24);
				const hv = new DataView(head.buffer);
				hv.setBigUint64(0, BigInt(i + 1), true);
				hv.setBigUint64(8, BigInt(node.ino), true);
				hv.setUint32(16, name.length, true);
				hv.setUint8(20, node instanceof Dir ? FILETYPE.DIR : FILETYPE.FILE);
				const entry = new Uint8Array(24 + name.length);
				entry.set(head);
				entry.set(name, 24);
				// (the last one cut at the end of the buffer: the caller reads again from its cookie)
				const n = Math.min(entry.length, end - at);
				m.set(entry.subarray(0, n), at);
				at += n;
			}
			v.setUint32(used, at - buf, true);
			return E.SUCCESS;
		},
		path_open(dirfd, _dirflags, p, n, oflags, _rb, _ri, fdflags, fdPtr) {
			const r = resolve(dirfd, p, n);
			if (!r) return E.BADF;
			const { parent, name, full } = r;
			let node = name === undefined ? fs.root : parent?.entries.get(name);
			if (!parent && name !== undefined) return E.NOENT;
			if (node && oflags & 4 && oflags & 1) return E.EXIST;
			if (!node) {
				if (!(oflags & 1)) return E.NOENT;
				node = new File();
				parent.entries.set(name, node);
			}
			if (oflags & 2 && !(node instanceof Dir)) return E.NOTDIR;
			if (oflags & 8 && node instanceof File) node.size = 0;
			const fd = free();
			fds[fd] = { node, path: full, pos: 0, append: !!(fdflags & 1) };
			if (node instanceof File) onOpen(full, !!(oflags & 1));
			view().setUint32(fdPtr, fd, true);
			return E.SUCCESS;
		},
		path_filestat_get(dirfd, _flags, p, n, ptr) {
			const r = resolve(dirfd, p, n);
			if (!r) return E.BADF;
			const node = r.name === undefined ? fs.root : r.parent?.entries.get(r.name);
			return node ? filestat(node, ptr) : E.NOENT;
		},
		path_filestat_set_times: () => E.SUCCESS,
		path_create_directory(dirfd, p, n) {
			const r = resolve(dirfd, p, n);
			if (!r?.parent) return E.NOENT;
			if (r.parent.entries.has(r.name)) return E.EXIST;
			r.parent.entries.set(r.name, new Dir());
			return E.SUCCESS;
		},
		path_remove_directory(dirfd, p, n) {
			const r = resolve(dirfd, p, n);
			const node = r?.parent?.entries.get(r.name);
			if (!node) return E.NOENT;
			if (!(node instanceof Dir)) return E.NOTDIR;
			if (node.entries.size) return E.NOTEMPTY;
			r.parent.entries.delete(r.name);
			return E.SUCCESS;
		},
		path_unlink_file(dirfd, p, n) {
			const r = resolve(dirfd, p, n);
			const node = r?.parent?.entries.get(r.name);
			if (!node) return E.NOENT;
			if (node instanceof Dir) return E.ISDIR;
			r.parent.entries.delete(r.name);
			return E.SUCCESS;
		},
		path_rename(fd, p, n, newFd, np, nn) {
			const a = resolve(fd, p, n), b = resolve(newFd, np, nn);
			const node = a?.parent?.entries.get(a.name);
			if (!node) return E.NOENT;
			if (!b?.parent) return E.NOENT;
			a.parent.entries.delete(a.name);
			b.parent.entries.set(b.name, node);
			return E.SUCCESS;
		},
		path_readlink: () => E.INVAL,
		path_symlink: () => E.NOSYS,
		path_link: () => E.NOSYS,
		// (clock subscriptions fire at once: nothing here waits)
		poll_oneoff(inp, out, nsubs, nevents) {
			const v = view();
			for (let i = 0; i < nsubs; i++) {
				const s = inp + i * 48, e = out + i * 32;
				v.setBigUint64(e, v.getBigUint64(s, true), true);
				v.setUint16(e + 8, 0, true);
				v.setUint8(e + 10, v.getUint8(s + 8));
			}
			v.setUint32(nevents, nsubs, true);
			return E.SUCCESS;
		},
		proc_exit(code) {
			throw new Exit(code);
		},
		sched_yield: () => E.SUCCESS,
	};

	return {
		imports,
		// runs _start; the exit code (0 when main returns)
		start(instance) {
			memory = instance.exports.memory;
			try {
				instance.exports._start();
				return 0;
			} catch (e) {
				if (e instanceof Exit) return e.code;
				throw e;
			} finally {
				flush(1, true);
				flush(2, true);
			}
		},
	};
}
