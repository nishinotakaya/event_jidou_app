# playwright-ruby-client と npm playwright のバージョン不一致対策
# Chromium が送信する新しい ChannelOwner タイプ（Debugger 等）が
# gem に未定義の場合に NameError でクラッシュするのを防ぐ。
Rails.application.config.after_initialize do
  require 'playwright' rescue nil
  if defined?(Playwright::ChannelOwners) && defined?(Playwright::ChannelOwner)
    %w[Debugger].each do |type|
      unless Playwright::ChannelOwners.const_defined?(type)
        Playwright::ChannelOwners.const_set(type, Class.new(Playwright::ChannelOwner))
        Rails.logger.info "[PlaywrightPatch] Stubbed missing ChannelOwner: #{type}"
      end
    end
  end
end
