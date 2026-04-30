module Mcp
  module Tools
    # Returns every Library the user belongs to (owned or invited as a
    # member), with a books_count for context. No arguments.
    class ListMyLibraries < Mcp::Tool
      NAME = "list_my_libraries"
      DESCRIPTION = "Lista las bibliotecas del usuario (propias y aquellas a las que pertenece como miembro), con el número de libros de cada una."
      INPUT_SCHEMA = {
        type: "object",
        properties: {},
        additionalProperties: false
      }.freeze

      def call
        @user.libraries.includes(:books).map do |library|
          {
            id: library.id,
            name: library.name,
            books_count: library.books.size
          }
        end
      end
    end
  end
end
