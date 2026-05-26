module Eval
  # In-memory double that quacks like ShelfPhoto for the eval runner — we
  # don't want to write rows to the dev DB just to call ClaudeBookIdentifier
  # against fixture images. Only the methods the identifier touches are
  # implemented: `id`, `library_id`, and an `image` substitute exposing
  # `filename` and `download`.
  class FakeShelfPhoto
    Image = Struct.new(:filename, :bytes) do
      def attached? = true
      def download = bytes
    end

    attr_reader :id, :library_id, :image

    def initialize(id:, image_path:, library_id: nil)
      @id = id
      @library_id = library_id
      @image = Image.new(File.basename(image_path), File.binread(image_path))
    end
  end
end
