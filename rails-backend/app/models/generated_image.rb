class GeneratedImage < ApplicationRecord
  belongs_to :user, optional: true

  validates :data, presence: true
  validates :source, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def as_json_safe
    {
      id: id,
      source: source,
      filename: filename,
      contentType: content_type,
      byteSize: byte_size,
      prompt: prompt,
      style: style,
      itemId: item_id,
      createdAt: created_at,
      url: Rails.application.routes.url_helpers.api_generated_image_path(id),
    }
  end
end
