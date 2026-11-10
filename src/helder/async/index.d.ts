// helder.async for TypeScript programs (helder.typescript): a program's
// promises and timers already run on helder.async's loop (its async
// functions as the graph's async computations, DESIGN.md 7.4); these are
// helder.async's own tasks, each a promise to the program (a Task<T> is a
// Promise<T>). Its HTTP client and server are a whole package: their
// coroutines are the program's async functions (helder.typescript.api.Coroutines).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Client: "helder.async.http.Client", Reply: "helder.async.http.Client.Reply", HxCoro_helder_async_http_Client_chunked: "helder.async.http.Client.HxCoro_helder_async_http_Client_chunked", HxCoro_helder_async_http_Client_read: "helder.async.http.Client.HxCoro_helder_async_http_Client_read", HxCoro_helder_async_http_Client_request: "helder.async.http.Client.HxCoro_helder_async_http_Client_request", Http: "helder.async.http.Http", Request: "helder.async.http.Http.Request", Response: "helder.async.http.Http.Response", HxCoro_helder_async_http_Request_read: "helder.async.http.Http.HxCoro_helder_async_http_Request_read", HxCoro_helder_async_http_Response_write: "helder.async.http.Http.HxCoro_helder_async_http_Response_write", HxCoro_helder_async_http_Http_connection: "helder.async.http.Http.HxCoro_helder_async_http_Http_connection", HxCoro_helder_async_http_Http_AnonFunc0: "helder.async.http.Http.HxCoro_helder_async_http_Http_AnonFunc0", HxCoro_helder_async_http_Http_serve: "helder.async.http.Http.HxCoro_helder_async_http_Http_serve", WebSocket: "helder.async.http.WebSocket", HxCoro_helder_async_http_WebSocket_upgrade: "helder.async.http.WebSocket.HxCoro_helder_async_http_WebSocket_upgrade", HxCoro_helder_async_http_WebSocket_connect: "helder.async.http.WebSocket.HxCoro_helder_async_http_WebSocket_connect", HxCoro_helder_async_http_WebSocket_frame: "helder.async.http.WebSocket.HxCoro_helder_async_http_WebSocket_frame", HxCoro_helder_async_http_WebSocket_receive: "helder.async.http.WebSocket.HxCoro_helder_async_http_WebSocket_receive", HxCoro_helder_async_http_WebSocket_send: "helder.async.http.WebSocket.HxCoro_helder_async_http_WebSocket_send", HxCoro_helder_async_http_WebSocket_ping: "helder.async.http.WebSocket.HxCoro_helder_async_http_WebSocket_ping", HxCoro_helder_async_http_WebSocket_close: "helder.async.http.WebSocket.HxCoro_helder_async_http_WebSocket_close", Tasks: "helder.async.Tasks", __module: "helder.async.TypeScript"};

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

export declare class HxCoro_helder_async_http_Client_chunked {
	constructor(completion: unknown, r: unknown);
	invokeResume(): unknown;
	_hx_hoisted107427: unknown;
	_hx_hoisted107431: number | null;
	_hx_hoisted107428: unknown;
	_hx_hoisted107432: string | null;
	_hx_hoisted107429: string | null;
	_hx_hoisted107437: Uint8Array;
}

export declare class HxCoro_helder_async_http_Client_read {
	constructor(completion: unknown, r: unknown, head: boolean);
	invokeResume(): unknown;
	_hx_hoisted107305: string | null;
	_hx_hoisted107496: Uint8Array;
	_hx_hoisted107310: string | null;
	_hx_hoisted107175: unknown;
	_hx_hoisted107346: string | null;
	_hx_hoisted107309: unknown;
	_hx_hoisted107311: number;
	_hx_hoisted107176: boolean;
	_hx_hoisted107308: number | null;
	_hx_hoisted107494: Uint8Array;
	_hx_hoisted107495: Uint8Array;
}

export declare class HxCoro_helder_async_http_Client_request {
	constructor(completion: unknown, url: string, options: RequestOptions | null);
	invokeResume(): unknown;
	_hx_hoisted106920: string;
	_hx_hoisted107106: unknown;
	_hx_hoisted107550: Reply;
	_hx_hoisted106906: string;
	_hx_hoisted106907: RequestOptions | null;
	_hx_hoisted106934: Uint8Array | null;
	_hx_hoisted106935: unknown;
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

// the next request on the connection; null at its end
export declare class HxCoro_helder_async_http_Request_read {
	// the next request on the connection; null at its end
	constructor(completion: unknown, s: unknown, r: unknown);
	// the next request on the connection; null at its end
	invokeResume(): unknown;
	// the next request on the connection; null at its end
	_hx_hoisted107738: unknown;
	// the next request on the connection; null at its end
	_hx_hoisted107770: Request;
	// the next request on the connection; null at its end
	_hx_hoisted107740: string | null;
	// the next request on the connection; null at its end
	_hx_hoisted107794: Uint8Array;
	// the next request on the connection; null at its end
	_hx_hoisted107744: number;
	// the next request on the connection; null at its end
	_hx_hoisted107739: unknown;
	// the next request on the connection; null at its end
	_hx_hoisted107742: unknown;
	// the next request on the connection; null at its end
	_hx_hoisted107777: number;
	// the next request on the connection; null at its end
	_hx_hoisted107741: string[];
	// the next request on the connection; null at its end
	_hx_hoisted107743: string | null;
}

export declare class HxCoro_helder_async_http_Response_write {
	constructor(completion: unknown, s: unknown, head: boolean, keepAlive: boolean, _hx_captured: Response);
	_hx_captured: Response;
	invokeResume(): unknown;
	_hx_hoisted107870: boolean;
	_hx_hoisted107869: boolean;
	_hx_hoisted107868: unknown;
}

export declare class HxCoro_helder_async_http_Http_connection {
	constructor(completion: unknown, s: unknown, handler: any);
	invokeResume(): unknown;
	_hx_hoisted107830: unknown;
	_hx_hoisted107737: boolean;
	_hx_hoisted107855: Response | null;
	_hx_hoisted107736: unknown;
	_hx_hoisted107735: any;
	_hx_hoisted107734: unknown;
	_hx_hoisted107829: Request | null;
}

export declare class HxCoro_helder_async_http_Http_AnonFunc0 {
	constructor(completion: unknown, _hx_captured: () => unknown);
	_hx_captured: (() => unknown);
	invokeResume(): unknown;
}

export declare class HxCoro_helder_async_http_Http_serve {
	constructor(completion: unknown, server: unknown, handler: any);
	invokeResume(): unknown;
	_hx_hoisted107610: unknown | null;
	_hx_hoisted107593: Array<unknown | null>;
	_hx_hoisted107595: unknown | null;
	_hx_hoisted107585: unknown;
	_hx_hoisted107586: any;
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

// the request's connection taken over (Http.serve's handler returns null after)
export declare class HxCoro_helder_async_http_WebSocket_upgrade {
	// the request's connection taken over (Http.serve's handler returns null after)
	constructor(completion: unknown, req: Request);
	// the request's connection taken over (Http.serve's handler returns null after)
	invokeResume(): unknown;
	// the request's connection taken over (Http.serve's handler returns null after)
	_hx_hoisted108041: Request;
}

export declare class HxCoro_helder_async_http_WebSocket_connect {
	constructor(completion: unknown, host: string, port: number, path: string);
	invokeResume(): unknown;
	_hx_hoisted108187: string;
	_hx_hoisted108190: unknown;
	_hx_hoisted108192: unknown;
	_hx_hoisted108194: string | null;
	_hx_hoisted108189: string;
	_hx_hoisted108188: number;
	_hx_hoisted108193: string | null;
}

export declare class HxCoro_helder_async_http_WebSocket_frame {
	constructor(completion: unknown, op: number, data: Uint8Array, _hx_captured: WebSocket);
	_hx_captured: WebSocket;
	invokeResume(): unknown;
	_hx_hoisted108363: number;
	_hx_hoisted108337: number;
	_hx_hoisted108344: number;
	_hx_hoisted108358: number;
	_hx_hoisted108338: number;
	_hx_hoisted108320: number;
	_hx_hoisted108334: number;
	_hx_hoisted108348: number;
	_hx_hoisted108312: Uint8Array;
	_hx_hoisted108335: number;
	_hx_hoisted108336: number;
	_hx_hoisted108350: number;
	_hx_hoisted108293: number;
	_hx_hoisted108298: number;
	_hx_hoisted108351: number;
	_hx_hoisted108361: number;
	_hx_hoisted108349: number;
	_hx_hoisted108294: Uint8Array;
	_hx_hoisted108346: number;
	_hx_hoisted108364: number;
	_hx_hoisted108362: number;
	_hx_hoisted108345: number;
	_hx_hoisted108295: WebSocket;
	_hx_hoisted108299: number;
	_hx_hoisted108347: number;
	_hx_hoisted108352: number;
}

// the next message; null once closed
export declare class HxCoro_helder_async_http_WebSocket_receive {
	// the next message; null once closed
	constructor(completion: unknown, _hx_captured: WebSocket);
	// the next message; null once closed
	_hx_captured: WebSocket;
	// the next message; null once closed
	invokeResume(): unknown;
	// the next message; null once closed
	_hx_hoisted108245: number;
	_hx_hoisted108286: number;
	// the next message; null once closed
	_hx_hoisted108227: WebSocket;
	// the next message; null once closed
	_hx_hoisted108266: Uint8Array | null;
	// the next message; null once closed
	_hx_hoisted108233: boolean;
	// the next message; null once closed
	_hx_hoisted108292: number;
	// the next message; null once closed
	_hx_hoisted108280: number;
	// the next message; null once closed
	_hx_hoisted108279: Uint8Array;
	// the next message; null once closed
	_hx_hoisted108291: number;
	// the next message; null once closed
	_hx_hoisted108226: unknown | null;
	// the next message; null once closed
	_hx_hoisted108241: boolean;
	// the next message; null once closed
	_hx_hoisted108237: number;
	// the next message; null once closed
	_hx_hoisted108246: Uint8Array;
	// the next message; null once closed
	_hx_hoisted108229: Uint8Array | null;
	_hx_hoisted108290: number;
	// the next message; null once closed
	_hx_hoisted108253: Uint8Array;
}

export declare class HxCoro_helder_async_http_WebSocket_send {
	constructor(completion: unknown, text: string, _hx_captured: WebSocket);
	_hx_captured: WebSocket;
	invokeResume(): unknown;
	_hx_hoisted108569: string;
}

export declare class HxCoro_helder_async_http_WebSocket_ping {
	constructor(completion: unknown, _hx_captured: WebSocket);
	_hx_captured: WebSocket;
	invokeResume(): unknown;
}

// a close sent (the other side's answer ends receive), the connection closed
export declare class HxCoro_helder_async_http_WebSocket_close {
	// a close sent (the other side's answer ends receive), the connection closed
	constructor(completion: unknown, code: number, _hx_captured: WebSocket);
	// a close sent (the other side's answer ends receive), the connection closed
	_hx_captured: WebSocket;
	// a close sent (the other side's answer ends receive), the connection closed
	invokeResume(): unknown;
	// a close sent (the other side's answer ends receive), the connection closed
	_hx_hoisted108618: Uint8Array;
	// a close sent (the other side's answer ends receive), the connection closed
	_hx_hoisted108604: number;
	// a close sent (the other side's answer ends receive), the connection closed
	_hx_hoisted108605: WebSocket;
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
