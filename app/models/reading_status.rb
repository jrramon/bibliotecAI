class ReadingStatus < ApplicationRecord
  belongs_to :user
  belongs_to :book

  enum :state, {reading: 0, read: 1, dropped: 2}, default: :reading

  validates :user_id, uniqueness: {scope: :book_id}

  scope :for_library, ->(library) { joins(:book).where(books: {library_id: library.id}) }
  scope :active, -> { where(state: :reading) }
end
