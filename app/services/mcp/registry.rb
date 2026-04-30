module Mcp
  # Single source of truth for the tools we expose over MCP. Adding a
  # tool means adding it here AND defining a class under Mcp::Tools.
  # The MCP server calls .all to enumerate them in tools/list and looks
  # them up by name in tools/call.
  module Registry
    def self.all
      [
        Mcp::Tools::ListMyLibraries,
        Mcp::Tools::SearchBooks,
        Mcp::Tools::ListMyWishlist
      ].freeze
    end

    def self.find(name)
      all.find { |t| t.name == name }
    end
  end
end
