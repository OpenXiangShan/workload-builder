set -e

"$CROSS_COMPILE"as "$SRC_DIR/hello.s" -o "$SRC_DIR/hello.o"
"$CROSS_COMPILE"ld "$SRC_DIR/hello.o" -o "$SRC_DIR/hello"
"$CROSS_COMPILE"strip -s "$SRC_DIR/hello"
cp "$SRC_DIR"/hello "$PKG_DIR"/init
