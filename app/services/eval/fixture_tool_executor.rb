require "json"

module Eval
  # Stand-in for Llm::ToolExecutor used by the Telegram-agent eval. Implements
  # the same #call(tool_name, arguments) -> String interface but returns canned,
  # deterministic data (shaped exactly like the real Mcp::Tools::* outputs) and
  # records the trajectory of tool calls — no DB, no mutations.
  #
  # The fixture is coherent with the real "En casa" library (has Asimov, Agile,
  # Kokoro…) + a small fixed wishlist, so real messages make sense against it.
  class FixtureToolExecutor
    LIBRARY = {id: 1, name: "En casa", books_count: 34}.freeze

    BOOKS = [
      {book_id: 101, title: "Fundación", author: "Isaac Asimov", published_year: 1951, library_id: 1, library: "En casa"},
      {book_id: 102, title: "Fundación e Imperio", author: "Isaac Asimov", published_year: 1952, library_id: 1, library: "En casa"},
      {book_id: 103, title: "Yo, Robot", author: "Isaac Asimov", published_year: 1950, library_id: 1, library: "En casa"},
      {book_id: 104, title: "El fin de la eternidad", author: "Isaac Asimov", published_year: 1955, library_id: 1, library: "En casa"},
      {book_id: 201, title: "The Culture Game", author: "Daniel Mezick", published_year: 2012, library_id: 1, library: "En casa"},
      {book_id: 202, title: "Reinventing Organizations", author: "Frédéric Laloux", published_year: 2014, library_id: 1, library: "En casa"},
      {book_id: 203, title: "Kokoro", author: "Natsume Soseki", published_year: 1914, library_id: 1, library: "En casa"}
    ].freeze

    WISHLIST = [
      {item_id: 9001, title: "Cybernetic Revolutionaries", author: "Eden Medina", isbn: nil, note: nil},
      {item_id: 9002, title: "Sombra y asombro", author: nil, isbn: nil, note: "del podcast"},
      {item_id: 9003, title: "Matrescencia", author: nil, isbn: nil, note: nil}
    ].freeze

    SEARCH_DEFAULT_LIMIT = 5
    SEARCH_MAX_LIMIT = 20

    attr_reader :trajectory

    def initialize
      @trajectory = []
    end

    # Mirrors Llm::ToolExecutor#call: returns the string fed back as the tool
    # message content, and records (tool_name, arguments) for scoring.
    def call(tool_name, arguments)
      args = arguments || {}
      @trajectory << {tool: tool_name, arguments: args}
      JSON.generate(dispatch(tool_name, args))
    end

    private

    def dispatch(tool_name, args)
      case tool_name
      when "list_my_libraries" then [LIBRARY]
      when "search_books" then search(args)
      when "list_my_wishlist" then WISHLIST
      when "add_to_wishlist" then add_to_wishlist(args)
      when "remove_from_wishlist" then remove_from_wishlist(args)
      when "process_book_cover_photo" then {ok: true, cover_photo_id: 1, intent: args["intent"].to_s}
      when "process_shelf_photo" then {ok: true, shelf_photo_id: 1}
      else {ok: false, error: "unknown tool: #{tool_name}"}
      end
    end

    def search(args)
      query = args["query"].to_s.strip.downcase
      return [] if query.empty?
      limit = clamp(args["limit"], SEARCH_DEFAULT_LIMIT, SEARCH_MAX_LIMIT)
      BOOKS.select { |b| "#{b[:title]} #{b[:author]}".downcase.include?(query) }.first(limit)
    end

    def add_to_wishlist(args)
      title = args["title"].to_s.strip
      return {ok: false, error: "title is required"} if title.empty?
      existing = WISHLIST.find { |w| w[:title].casecmp?(title) }
      {
        ok: true,
        item_id: existing ? existing[:item_id] : 9999,
        deduped: !existing.nil?,
        title: existing ? existing[:title] : title,
        author: existing ? existing[:author] : args["author"]
      }
    end

    def remove_from_wishlist(args)
      id = args["item_id"].to_i
      item = WISHLIST.find { |w| w[:item_id] == id }
      return {ok: false, error: "not found"} unless item
      {ok: true, item_id: id, title: item[:title]}
    end

    def clamp(raw, default, max)
      n = raw.to_i
      return default if n <= 0
      [n, max].min
    end
  end
end
