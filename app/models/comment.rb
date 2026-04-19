class Comment < ApplicationRecord
  belongs_to :book
  belongs_to :user

  has_rich_text :body

  validates :body, presence: true

  scope :recent, -> { order(created_at: :asc) }

  after_create_commit -> {
    broadcast_append_to [book, :comments],
      target: ActionView::RecordIdentifier.dom_id(book, :comments),
      partial: "comments/comment",
      locals: {comment: self}
  }
  after_destroy_commit -> { broadcast_remove_to [book, :comments] }
end
