# Playwright npm 1.58+ で追加された Debugger ChannelOwner に
# playwright-ruby-client が未対応のため、ダミークラスを定義して NameError を回避
begin
  require 'playwright'
  unless defined?(Playwright::ChannelOwners::Debugger)
    module Playwright
      module ChannelOwners
        class Debugger < ChannelOwner
        end
      end
    end
  end
rescue LoadError
  # playwright-ruby-client がインストールされていない環境では無視
end
