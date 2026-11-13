module MCPC
  # Turns server notifications into events.
  module NotificationEvents
    # Returns the event for *notification*, or nil when it has none or is malformed.
    def self.translate(notification : JSONRPC::Notification) : Event?
      params = notification.params.to_json
      case notification.method
      when "notifications/progress"               then Event::Progress.from_json(params)
      when "notifications/message"                then Event::LogMessage.from_json(params)
      when "notifications/resources/updated"      then Event::ResourceUpdated.from_json(params)
      when "notifications/tools/list_changed"     then Event::ToolsChanged.new
      when "notifications/prompts/list_changed"   then Event::PromptsChanged.new
      when "notifications/resources/list_changed" then Event::ResourcesChanged.new
      end
    rescue error : JSON::SerializableError | JSON::ParseException
      Log.warn { "ignored malformed #{notification.method}: #{error.message}" }
      nil
    end
  end
end
