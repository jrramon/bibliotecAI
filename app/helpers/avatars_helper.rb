module AvatarsHelper
  # Renders a single avatar: a circle with the user's initials on a color
  # deterministically derived from their email (see `avatar_slot`). No remote
  # image fetch — matches the kanji-stamp / spine-palette aesthetic.
  #
  # size: :sm | :md | :lg
  def avatar_for(user, size: :md, extra_classes: nil)
    return "".html_safe unless user
    classes = ["avatar", "avatar-#{size}", "avatar-slot-#{avatar_slot(user)}", extra_classes].compact.join(" ")
    tag.span(avatar_initials(user), class: classes, title: user.email, aria: {label: user.email})
  end

  # Renders up to `max` avatars overlapping, plus "+N" if there are more.
  def avatar_stack(users, max: 4, size: :sm)
    users = users.to_a.compact
    return "".html_safe if users.empty?
    shown = users.first(max)
    extra = users.size - shown.size
    stack = tag.span(class: "avatar-stack") do
      safe_join(shown.map { |u| avatar_for(u, size: size) })
    end
    return stack if extra <= 0
    safe_join([stack, tag.span("+#{extra}", class: "avatar-more")])
  end

  private

  # Two-character label. "jose.ramon@x" → "JR", "alice@x" → "AL".
  def avatar_initials(user)
    local = user.email.to_s.split("@").first.to_s
    parts = local.split(/[._+-]+/).reject(&:empty?)
    if parts.size >= 2
      (parts[0][0].to_s + parts[1][0].to_s).upcase
    else
      local[0, 2].to_s.upcase
    end
  end

  # Stable 0..9 slot. Uses the same palette as book spines.
  def avatar_slot(user)
    Digest::MD5.hexdigest(user.email.to_s)[0, 2].to_i(16) % 10
  end
end
