// helder.async for TypeScript programs (helder.typescript): a program's
// promises and timers already run on helder.async's loop (its async
// functions as the graph's async computations, DESIGN.md 7.4); these are
// helder.async's own tasks, each a promise to the program (a Task<T> is a
// Promise<T>). Its HTTP client and server are a whole package: their
// coroutines are the program's async functions (helder.typescript.api.Coroutines).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Client: "helder.async.http.Client", Reply: "helder.async.http.Client.Reply", Http: "helder.async.http.Http", Request: "helder.async.http.Http.Request", Response: "helder.async.http.Http.Response", WebSocket: "helder.async.http.WebSocket", Tasks: "helder.async.Tasks", __module: "helder.async.TypeScript"};

export type RequestOptions = { method?: string; headers?: unknown; body?: Uint8Array; text?: string; contentType?: string };

// An HTTP/1.1 client on helder.async's TCP, for talking to a local server
// (plain http, one connection a request): the body read by Content-Length,
// chunked or until the server closes. No TLS, no redirects, no
// compression asked for.
//
//   var res = Client.request("http://127.0.0.1:4983/", {method: "POST", body: '{"type":"init"}',
//     headers: ["content-type" => "application/json"]});
//   trace(res.status, res.text());
export declare class Client {
	static request(url: string, options?: RequestOptions): Promise<Reply>;
}

export declare class Reply {
	constructor(status: number, headers: unknown, body: Uint8Array);
	readonly status: number;
	// names in lower case
	readonly headers: unknown;
	readonly body: Uint8Array;
	header(name: string): string | null;
	text(): string;
}

// A minimal HTTP/1.1 server on helder.async's TCP: enough for a dev server.
// Each connection is a child task of the caller's; its requests (kept alive)
// go to the handler in turn, whose Response is written back; a null one
// means the handler took the connection over (WebSocket.upgrade). Bodies
// by Content-Length (no chunked requests); an error in the handler is a 500
// and the connection closed, the server going on.
//
//   var server = Server.listen("127.0.0.1", 8080);
//   Http.serve(server, req -> Http.file("public", req.path) ?? Response.text("not found", 404));
export declare class Http {
	static serve(server: unknown, handler: any): Promise<unknown>;
	// the file at root + path (its index.html for a directory), as a response
	// with its type; null when there is none (or the path leaves root)
	static file(root: string, path: string): Response | null;
	static mime(path: string): string;
}

export declare class Request {
	// the next request on the connection; null at its end
	static read(s: unknown, r: unknown): Promise<Request | null>;
	readonly method: string;
	// decoded, without the query
	readonly path: string;
	readonly query: string;
	readonly version: string;
	// names in lower case
	readonly headers: unknown;
	readonly body: Uint8Array;
	readonly socket: unknown;
	readonly reader: unknown;
	header(name: string): string | null;
	keepAlive(): boolean;
}

export declare class Response {
	constructor(status?: number, body?: Uint8Array);
	static text(s: string, status?: number, type?: string): Response;
	status: number;
	// names in lower case
	readonly headers: unknown;
	body: Uint8Array;
	write(s: unknown, head: boolean, keepAlive: boolean): Promise<unknown>;
}

// A WebSocket (RFC 6455) on a connection: a server's, from an HTTP request
// (upgrade), or a client's (connect). Messages are text (binary ones come
// as their bytes' string); pings are answered, fragments joined, a close
// answered. Sends are whole messages, one at a time (a Lock), so several
// tasks may send while one receives.
//
//   Http.serve(server, req -> {
//     if (req.path != "/ws") return Http.file("public", req.path);
//     var ws = WebSocket.upgrade(req);
//     var m; while ((m = ws.receive()) != null) ws.send("echo " + m);
//     null;
//   });
export declare class WebSocket {
	// whether the request asks for a WebSocket
	static wants(req: Request): boolean;
	// the request's connection taken over (Http.serve's handler returns null after)
	static upgrade(req: Request): Promise<WebSocket>;
	static connect(host: string, port: number, path?: string): Promise<WebSocket>;
	readonly closed: boolean;
	// the next message; null once closed
	receive(): Promise<string | null>;
	send(text: string): Promise<unknown>;
	ping(): Promise<unknown>;
	// a close sent (the other side's answer ends receive), the connection closed
	close(code?: number): Promise<unknown>;
}

// helder.async for code that has no coroutines (a TypeScript program,
// helder/async): each a task started now on this thread's loop, which
// TypeScript awaits as a promise (cancelling the promise cancels it).
export declare class Tasks {
	// done after that many seconds
	static delay(seconds: number): Promise<unknown>;
	// a file's bytes: natively read, in the browser fetched (Fetch.bytes)
	static bytes(path: string): Promise<Uint8Array>;
}

export declare const delay: typeof Tasks.delay;
export declare const readBytes: typeof Tasks.bytes;
