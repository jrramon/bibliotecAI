module Mcp
  module Tools
    # Shared blob-copy helper for the two photo-staging tools. The
    # Telegram-uploaded blob lives on `TelegramMessage#photo`; we copy
    # its bytes into the CoverPhoto or ShelfPhoto's own attachment so
    # those models stand on their own without back-references.
    module PhotoBlobCopier
      def self.call(src:, dst_attachment:)
        dst_attachment.attach(
          io: StringIO.new(src.download),
          filename: src.filename.to_s,
          content_type: src.content_type || "image/jpeg"
        )
      end
    end
  end
end
