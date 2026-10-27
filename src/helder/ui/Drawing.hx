package helder.ui;

import helder.image.Image;

// A vector drawing an Image was rendered from (Image.drawing: an Svg), for
// a writer to draw as vectors instead of the pixels
interface Drawing {}

// what Svg.render keeps as the image's drawing: the drawing in its colour
// (currentColor's): var d:ImageDrawing = image.drawing
typedef ImageDrawing = {svg:Drawing, color:Color};
