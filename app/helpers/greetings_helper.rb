module GreetingsHelper
  # Time-of-day greeting + the local part of the user's email (pre-@).
  # When we grow a display_name column this helper is the only caller
  # that needs updating.
  def greeting_for(user, now: Time.current)
    "#{time_of_day_greeting(now)}, #{display_name_for(user)}"
  end

  def display_name_for(user)
    user.email.to_s.split("@").first.presence || "amigo"
  end

  # Counts of new library activity (books added, comments posted, cover
  # photos processed) by *other* users since the viewer's previous visit.
  # Returns an Integer. Zero means "nothing new" and the greeting hides
  # the counter line.
  def new_since_last_visit(user, previous_visit)
    return 0 if user.nil? || previous_visit.nil?
    library_ids = user.libraries.select(:id)

    new_books = Book.where(library_id: library_ids)
      .where("created_at > ?", previous_visit)
      .where.not(added_by_user_id: user.id)
      .count
    new_comments = Comment.joins(:book)
      .where(books: {library_id: library_ids})
      .where("comments.created_at > ?", previous_visit)
      .where.not(user_id: user.id)
      .count
    new_books + new_comments
  end

  private

  def time_of_day_greeting(now)
    case now.hour
    when 5..12  then "Buenos días"
    when 13..20 then "Buenas tardes"
    else             "Buenas noches"
    end
  end
end
