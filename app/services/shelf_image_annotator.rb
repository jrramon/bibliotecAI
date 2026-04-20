require "mini_magick"

class ShelfImageAnnotator
  STROKE_COLOR = "#D63A3A"
  STROKE_WIDTH = 8

  def self.call(...) = new(...).call

  def initialize(shelf_photo, boxes)
    @shelf_photo = shelf_photo
    @boxes = Array(boxes)
  end

  def call
    return if @boxes.empty?

    base = Rails.root.join("tmp/shelf_photos")
    FileUtils.mkdir_p(base)
    source_path = base.join("annotate-#{@shelf_photo.id}-src#{ext}").to_s
    output_path = base.join("annotate-#{@shelf_photo.id}-out#{ext}").to_s

    File.binwrite(source_path, @shelf_photo.image.download)

    image = MiniMagick::Image.open(source_path)
    image.combine_options do |c|
      c.fill "none"
      c.stroke STROKE_COLOR
      c.strokewidth STROKE_WIDTH
      @boxes.each do |box|
        x1, y1, x2, y2 = box.values_at("x1", "y1", "x2", "y2").map(&:to_i)
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
