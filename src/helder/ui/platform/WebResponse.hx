package helder.ui.platform;

import haxe.io.Bytes;

// A response of WebContent's: its status, MIME type, headers and body
class WebResponse {
	public var status:Int;
	public var mime:String;
	public final headers = new Map<String, String>();
	public var body:Bytes;

	public function new(status:Int, mime:String, body:Bytes) {
		this.status = status;
		this.mime = mime;
		this.body = body;
	}

	public static function bytes(b:Bytes, mime:String):WebResponse
		return new WebResponse(200, mime, b);

	public static function text(s:String, mime = "text/plain"):WebResponse
		return new WebResponse(200, mime, Bytes.ofString(s));

	public static function error(code:Int, mime:String, s:String):WebResponse
		return new WebResponse(code, mime, Bytes.ofString(s));

	// the reason phrase of a status
	public static function reason(code:Int):String
		return switch code {
			case 200: "OK";
			case 204: "No Content";
			case 304: "Not Modified";
			case 400: "Bad Request";
			case 403: "Forbidden";
			case 404: "Not Found";
			case 500: "Internal Server Error";
			case _: "Status";
		}

	// a path's MIME type, by its extension (text as UTF-8)
	public static function mimeOf(path:String):String
		return switch haxe.io.Path.extension(path).toLowerCase() {
			case "html" | "htm": "text/html; charset=utf-8";
			case "js" | "mjs": "text/javascript; charset=utf-8";
			case "css": "text/css; charset=utf-8";
			case "json" | "map": "application/json; charset=utf-8";
			case "wasm": "application/wasm";
			case "svg": "image/svg+xml";
			case "png": "image/png";
			case "jpg" | "jpeg": "image/jpeg";
			case "gif": "image/gif";
			case "webp": "image/webp";
			case "avif": "image/avif";
			case "ico": "image/x-icon";
			case "woff": "font/woff";
			case "woff2": "font/woff2";
			case "ttf": "font/ttf";
			case "otf": "font/otf";
			case "txt": "text/plain; charset=utf-8";
			case "xml": "application/xml";
			case "mp4": "video/mp4";
			case "webm": "video/webm";
			case "mp3": "audio/mpeg";
			case "ogg": "audio/ogg";
			case "wav": "audio/wav";
			case "glb": "model/gltf-binary";
			case "gltf": "model/gltf+json";
			case "webmanifest": "application/manifest+json";
			case _: "application/octet-stream";
		}
}
