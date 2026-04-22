module AvatarsHelper
  # Renders a single avatar. Uses the user's uploaded image if present;
  # otherwise falls back to initials on a deterministic colour derived
  # from the email — the kanji-stamp aesthetic is preserved for users
  # who never set a photo.
  #
  # size: :sm | :md | :lg
  def avatar_for(user, size: :md, extra_classes: nil)
    return "".html_safe unless user

    if user.respond_to?(:avatar) && user.avatar.attached?
      image_classes = ["avatar", "avatar-#{size}", "avatar--image", extra_classes].compact.join(" ")
      variant = (size == :lg) ? :thumb : :small
      image_tag user.avatar.variant(variant), class: image_classes,
                                              alt: user.display_name,
                                              title: user.display_name
    else
      classes = ["avatar", "avatar-#{size}", "avatar-slot-#{avatar_slot(user)}", extra_classes].compact.join(" ")
      tag.span(avatar_initials(user), class: classes,
                                      title: user.display_name,
                                      aria: {label: user.display_name})
    end
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

  # Two-character label. Prefers "name" when set (first letter of the
  # first two words), else splits on email separators.
  def avatar_initials(user)
    if user.name.to_s.strip.present?
      words = user.name.strip.split(/\s+/)
      first = words[0][0].to_s
      second = words[1]&.slice(0).to_s
      return (first + second).upcase.slice(0, 2)
    end

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
