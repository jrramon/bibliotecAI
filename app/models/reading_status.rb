class ReadingStatus < ApplicationRecord
  belongs_to :user
  belongs_to :book

  enum :state, {reading: 0, read: 1, dropped: 2}, default: :reading

  scope :for_library, ->(library) { joins(:book).where(books: {library_id: library.id}) }
  scope :active, -> { where(state: :reading) }
  scope :completed, -> { where(state: :read) }
  scope :ordered, -> { order(created_at: :desc) }
end
