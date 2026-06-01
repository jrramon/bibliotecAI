# Invita a usuarios independientes (cada uno con su propia biblioteca).
#
# Crea una Invitation sin biblioteca por cada email y envía el correo con el
# link. Al aceptar, el invitado se registra y obtiene su biblioteca propia.
#
# Uso:
#   bin/rails runner script/invite_users.rb nuevo@persona.com otro@persona.com
#
# El invitador (invited_by) es, por orden: ENV["INVITER_EMAIL"], o
# joserra@wearetayari.com, o el primer usuario. Cámbialo con:
#   INVITER_EMAIL=tu@email.com bin/rails runner script/invite_users.rb ...

emails = ARGV.map { |e| e.to_s.strip.downcase }.reject(&:empty?).uniq

if emails.empty?
  abort "Uso: bin/rails runner script/invite_users.rb email1 [email2 ...]"
end

inviter =
  User.find_by(email: ENV["INVITER_EMAIL"]) ||
  User.find_by(email: "joserra@wearetayari.com") ||
  User.first

abort "No hay usuario invitador. Define INVITER_EMAIL." unless inviter
puts "Invitador: #{inviter.email}\n\n"

emails.each do |email|
  if User.exists?(email: email)
    puts "· #{email} — ya tiene cuenta, omitido"
    next
  end

  # Idempotente: reutiliza una invitación de cuenta pendiente si ya existe.
  invitation =
    Invitation.pending.find_by(email: email, library_id: nil) ||
    Invitation.create!(email: email, invited_by: inviter, library: nil)

  InvitationsMailer.invite(invitation).deliver_now

  url =
    begin
      opts = ActionMailer::Base.default_url_options
      Rails.application.routes.url_helpers.invitation_url(token: invitation.token, **opts)
    rescue
      "(configura default_url_options para ver el link) token=#{invitation.token}"
    end

  puts "✓ #{email} — invitado · expira #{invitation.expires_at.to_date}"
  puts "  #{url}"
end

puts "\nListo: #{emails.size} email(s) procesado(s)."
