module Mcp
  module Tools
    # Stages the photo attached to the *current* TelegramMessage as a
    # ShelfPhoto and kicks off BookIdentificationJob (the multi-book
    # detector). Same identity model as ProcessBookCoverPhoto: the
    # current message comes from the signed token, not arguments.
    #
    # No `intent`: shelves always add Books to the user's default
    # library (the library has no concept of "wishlist for a whole
    # shelf"). The job's results are sent back via
    # Telegram::NotifyIdentifiedShelf with a link to the annotated
    # image on the web.
    class ProcessShelfPhoto < Mcp::Tool
      NAME = "process_shelf_photo"
      DESCRIPTION = "Procesa la foto adjunta al mensaje actual como una estantería con VARIOS libros. " \
        "Úsala cuando el usuario manda una foto que muestra varios lomos/portadas a la vez. " \
        "La identificación corre en background; tu respuesta debe avisar al usuario de que estás procesando."
      INPUT_SCHEMA = {
        type: "object",
        properties: {},
        additionalProperties: false
      }.freeze

      def call
        msg = TelegramMessage.find_by(id: @context[:message_id], user_id: @user.id)
        return error("no current telegram message") unless msg
        return error("no photo attached to the current message") unless msg.photo.attached?

        library = @user.default_library
        return error("user has no library yet — ask them to create one in the web app first") unless library

        shelf = library.shelf_photos.build(
          uploaded_by_user: @user,
          telegram_chat_id: msg.chat_id
        )
        Mcp::Tools::PhotoBlobCopier.call(src: msg.photo.blob, dst_attachment: shelf.image)
        shelf.save!

        BookIdentificationJob.perform_later(shelf.id)

        {ok: true, shelf_photo_id: shelf.id}
      end

      private

      def error(msg) = {ok: false, error: msg}
    end
  end
end
