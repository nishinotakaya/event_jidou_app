class AppSetting < ApplicationRecord
  KNOWN_KEYS = %w[
    event_gen_date event_gen_time event_gen_end_time
    openai_api_key
    dalle_api_key
    lme_gen_checked lme_gen_subtype lme_send_date lme_send_time
    lme_zoom_url lme_meeting_id lme_passcode
    post_selected_sites
  ].freeze

  validates :key, presence: true, uniqueness: true

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    setting = find_or_initialize_by(key: key)
    setting.update!(value: value.to_s)
    setting
  end

  def self.bulk_get(keys)
    where(key: keys).each_with_object({}) { |s, h| h[s.key] = s.value }
  end

  def self.bulk_set(pairs)
    pairs.each { |k, v| set(k, v) }
  end
end
