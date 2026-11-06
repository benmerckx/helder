package helder.ui;

// what Svg.render keeps as the image's drawing (Image.drawing), for a
// writer to draw as vectors instead of the pixels: the drawing in its
// colour (currentColor's): var d:ImageDrawing = image.drawing
typedef ImageDrawing = {svg:Svg, color:Color};
