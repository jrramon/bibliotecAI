require "mini_magick"

class ShelfImageAnnotator
  STROKE_COLOR = "#D63A3A"
  MIN_STROKE_WIDTH = 6

  def self.call(...) = new(...).call

  # `reported_width` / `reported_height` are Claude's view of the image.
  # Claude Code's multimodal input is downsampled to roughly 1568px on the
  # long edge, so its bounding boxes are in a much smaller coordinate
  # space than the original upload. We scale each box back up to the real
  # pixel dimensions before drawing.
  def initialize(shelf_photo, boxes, reported_width: nil, reported_height: nil)
    @shelf_photo = shelf_photo
    @boxes = Array(boxes)
    @reported_width = reported_width.to_i
    @reported_height = reported_height.to_i
  end

  def call
    return if @boxes.empty?

    base = Rails.root.join("tmp/shelf_photos")
    FileUtils.mkdir_p(base)
    source_path = base.join("annotate-#{@shelf_photo.id}-src#{ext}").to_s
    output_path = base.join("annotate-#{@shelf_photo.id}-out#{ext}").to_s

    File.binwrite(source_path, @shelf_photo.image.download)

    image = MiniMagick::Image.open(source_path)
    actual_w, actual_h = image.width, image.height
    scale_x = (@reported_width.positive? ? actual_w.to_f / @reported_width : 1.0)
    scale_y = (@reported_height.positive? ? actual_h.to_f / @reported_height : 1.0)
    stroke = [(actual_w / 250.0).round, MIN_STROKE_WIDTH].max

    image.combine_options do |c|
      c.fill "none"
      c.stroke STROKE_COLOR
      c.strokewidth stroke
      @boxes.each do |box|
        x1 = (box["x1"].to_i * scale_x).round
        y1 = (box["y1"].to_i * scale_y).round
        x2 = (box["x2"].to_i * scale_x).round
        y2 = (box["y2"].to_i * scale_y).round
        c.draw "rectangle #{x1},#{y1} #{x2},#{y2}"
      end
    end
    image.write(output_path)

    @shelf_photo.annotated_image.attach(
      io: File.open(output_path),
      filename: "annotated-#{@shelf_photo.image.filename}",
      content_type: @shelf_photo.image.content_type
    )
  ensure
    [source_path, output_path].each do |p|
      File.delete(p) if p && File.exist?(p)
    end
  end

  private

  def ext
    File.extname(@shelf_photo.image.filename.to_s).presence || ".jpg"
  end
end
