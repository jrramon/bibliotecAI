module Mcp
  module Tools
    # Stages the photo attached to the *current* TelegramMessage as a
    # CoverPhoto and kicks off CoverIdentificationJob. The current
    # message is identified by `context[:message_id]`, which is set
    # from the signed MCP session token — never from arguments — so
    # Claude can't point this at someone else's photo.
    #
    # `intent` is the only arg: "library" (default) creates a Book in
    # the user's default library; "wishlist" creates a WishlistItem
    # via the normal NotifyIdentifiedCover flow.
    class ProcessBookCoverPhoto < Mcp::Tool
      NAME = "process_book_cover_photo"
      DESCRIPTION = "Procesa la foto adjunta al mensaje actual como portada de UN libro. " \
        "Úsala cuando el usuario manda una foto de un único libro/portada. " \
        "Opcional `intent: 'wishlist'` apunta el libro a la wishlist en vez de añadirlo a la biblioteca. " \
        "La identificación corre en background; tu respuesta debe avisar al usuario de que estás procesando."
      INPUT_SCHEMA = {
        type: "object",
        properties: {
          intent: {
            type: "string",
            enum: %w[library wishlist],
            description: "library: añadir a la biblioteca del usuario (default). wishlist: apuntar en su wishlist."
          }
        },
        additionalProperties: false
      }.freeze

      def call
        msg = TelegramMessage.find_by(id: @context[:message_id], user_id: @user.id)
        return error("no current telegram message") unless msg
        return error("no photo attached to the current message") unless msg.photo.attached?

        library = @user.default_library
        return error("user has no library yet — ask them to create one in the web app first") unless library

        intent = (@arguments["intent"] == "wishlist") ? :wishlist : :library

        cover = library.cover_photos.build(
          uploaded_by_user: @user,
          telegram_chat_id: msg.chat_id,
          intent: intent
        )
        Mcp::Tools::PhotoBlobCopier.call(src: msg.photo.blob, dst_attachment: cover.image)
        cover.save!

        CoverIdentificationJob.perform_later(cover.id)

        {ok: true, cover_photo_id: cover.id, intent: intent.to_s}
      end

      private

      def error(msg) = {ok: false, error: msg}
    end
  end
end
