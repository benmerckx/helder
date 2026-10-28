// Asset: ".." in a path is a compile error (the path as it is, from its root)
class Parent {
	static function main()
		helder.asset.Asset.image("files/../files/pixels.png");
}
