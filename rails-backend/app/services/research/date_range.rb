module Research
  # 「いつ開催されるイベントを見たいか」を表す値オブジェクト（交流会リサーチの開催日条件）。
  #
  # ■ 終了したイベントは常に除外する
  #   開催日を過ぎたイベントはリサーチの邪魔にしかならないので、開始日は必ず「今日（JST）」以降にクランプする。
  #   ユーザーが過去日を指定しても今日まで切り上げるため、過去のイベントが表に出ることはない。
  #
  # ■ 絞り込みは2段構え
  #   1. サイト側の日付パラメータへ渡す（こくちーずプロ start_date / connpass start_from）。
  #      取得ページ数に上限があるので、サイト側で絞れるなら絞ったほうが取りこぼしが減る。
  #   2. 日付で絞れないサイトは取得後に filter で落とす。
  #   どの経路の結果も最後は必ず filter を通す（ResearchController）ので、
  #   サイト実装が 1. に対応していなくても終了イベントが表示に漏れることはない。
  class DateRange
    JST_OFFSET = "+09:00".freeze
    PARAM_FORMAT = "%Y-%m-%d".freeze

    attr_reader :from_date, :to_date

    # from / to は "2026-09-01" 形式の文字列（空欄可）。読めない文字列は未指定として扱う。
    def initialize(from: nil, to: nil)
      requested_from = self.class.parse_date(from)
      @to_date = self.class.parse_date(to)
      @from_date = [ requested_from, self.class.today ].compact.max
      @specified = requested_from.present? || @to_date.present?
    end

    def self.today
      Time.now.getlocal(JST_OFFSET).to_date
    end

    # フロントの <input type="date"> が送る "YYYY-MM-DD" だけを受け付ける。
    # Date.parse だと "8" のような入力まで日付として通ってしまうため strptime で厳密に読む。
    def self.parse_date(text)
      return nil if text.blank?

      Date.strptime(text.to_s, PARAM_FORMAT)
    rescue ArgumentError
      nil
    end

    # ユーザーが明示的に開催日を指定したか（未指定なら「今日以降すべて」）
    def specified?
      @specified
    end

    def filter(results)
      results.select { |result| include?(result) }
    end

    def include?(result)
      event_date = self.class.event_date(result)
      # 開催日が読み取れないイベントは「終了した」と断定できないので、条件未指定なら残す。
      # 逆に開催日を指定した検索では「条件を満たす」とも言えないので落とす。
      return !specified? if event_date.nil?
      return false if event_date < from_date
      return false if to_date && event_date > to_date

      true
    end

    def self.event_date(result)
      starts_at = result[:startsAt] || result["startsAt"]
      return nil if starts_at.blank?

      Time.iso8601(starts_at.to_s).getlocal(JST_OFFSET).to_date
    rescue ArgumentError
      nil
    end

    # サイト側の検索パラメータに渡す "YYYY-MM-DD"
    def from_param
      from_date.strftime(PARAM_FORMAT)
    end

    def to_param
      to_date&.strftime(PARAM_FORMAT)
    end
  end
end
