module Llm
  # Normalized single-shot request, provider-agnostic.
  #
  # - prompt:          fully compiled prompt text (the service builds it)
  # - image_paths:     absolute paths to local images (empty for text-only)
  # - model:           model id, or nil to use the provider default
  # - timeout:         seconds
  # - response_format: :json | :text (hint; providers may pass it through)
  Request = Struct.new(:prompt, :image_paths, :model, :timeout, :response_format, keyword_init: true)
end
