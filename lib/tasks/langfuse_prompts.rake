namespace :langfuse do
  namespace :prompts do
    desc "Sube/actualiza el prompt cover-identification en Langfuse (idempotente)"
    task seed: :environment do
      require "net/http"

      raise "Langfuse no está configurado (LANGFUSE_PUBLIC_KEY / SECRET_KEY)" unless Langfuse::Config.configured?

      seed_prompt(
        name: "cover-identification",
        body: ClaudeCoverIdentifier::PROMPT_TEMPLATE
      )
    end
  end
end

# Posts a new prompt version only when the local body differs from the
# latest in Langfuse — so re-running the task is a no-op when nothing has
# changed and you don't litter the prompt history with duplicates.
def seed_prompt(name:, body:, labels: ["production"])
  current = Langfuse::Prompt.fetch_remote(name)

  if current && current.body == body
    puts "[langfuse:prompts] #{name}: ya está al día (v#{current.version}), sin cambios"
    return
  end

  uri = URI.join(Langfuse::Config::HOST, "/api/public/v2/prompts")
  request = Net::HTTP::Post.new(uri)
  request.basic_auth(Langfuse::Config::PUBLIC_KEY, Langfuse::Config::SECRET_KEY)
  request["Content-Type"] = "application/json"
  request.body = JSON.generate({
    name: name,
    type: "text",
    prompt: body,
    labels: labels
  })

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request(request)
  end

  if (200..299).cover?(response.code.to_i)
    payload = JSON.parse(response.body)
    puts "[langfuse:prompts] #{name}: creada v#{payload["version"]} (labels=#{labels.join(",")})"
  else
    abort "[langfuse:prompts] #{name}: fallo #{response.code}: #{response.body.to_s.truncate(400)}"
  end
end
