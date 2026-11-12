require "./spec_helper"

describe "result types, read from the specification's examples" do
  it "reads every Tool example" do
    Dir.glob((FIXTURES / "Tool" / "*.json").to_s).each do |path|
      tool = Mcpc::Tool.from_json(File.read(path))
      tool.name.should_not be_empty
      tool.input_schema["type"].should eq("object")
    end
  end

  it "reads a tool's titles, schemas and hints" do
    tool = Mcpc::Tool.from_json(%({"name":"get_weather","title":"Weather","description":"Current weather",
      "inputSchema":{"type":"object"},"outputSchema":{"type":"object"},"annotations":{"readOnlyHint":true}}))
    tool.title.should eq("Weather")
    tool.output_schema.should_not be_nil
    tool.annotations.try(&.read_only_hint).should be_true
    tool.annotations.try(&.destructive_hint).should be_nil
  end

  it "reads a text tool result" do
    result = Mcpc::CallToolResult.from_json(fixture("CallToolResult", "result-with-unstructured-text"))
    result.error?.should be_false
    result.content.first.should be_a(Mcpc::TextContent)
    result.text.should_not be_empty
  end

  it "reads structured content beside the text" do
    result = Mcpc::CallToolResult.from_json(fixture("CallToolResult", "result-with-structured-content"))
    result.structured_content.should_not be_nil
  end

  it "reads a failed tool call as a result, not an error" do
    result = Mcpc::CallToolResult.from_json(fixture("CallToolResult", "invalid-tool-input-error"))
    result.error?.should be_true
    result.text.should_not be_empty
  end

  it "reads each kind of content block" do
    blocks = Array(Mcpc::Content).from_json(%([
      #{fixture("TextContent", Dir.children(FIXTURES / "TextContent").first.rchop(".json"))},
      #{fixture("ImageContent", Dir.children(FIXTURES / "ImageContent").first.rchop(".json"))},
      #{fixture("AudioContent", Dir.children(FIXTURES / "AudioContent").first.rchop(".json"))},
      #{fixture("ResourceLink", "file-resource-link")},
      #{fixture("EmbeddedResource", "embedded-file-resource-with-annotations")},
      {"type":"hologram","depth":3}]))

    blocks.map(&.class).should eq([Mcpc::TextContent, Mcpc::ImageContent, Mcpc::AudioContent,
                                   Mcpc::ResourceLink, Mcpc::EmbeddedResource, Mcpc::UnknownContent])
    blocks[1].as(Mcpc::ImageContent).mime_type.should start_with("image/")
    blocks[4].as(Mcpc::EmbeddedResource).resource.uri.should_not be_empty
    blocks[5].as(Mcpc::UnknownContent).raw["depth"].should eq(3)
  end

  it "reads resource contents" do
    result = JSON.parse(fixture("ReadResourceResult", "file-resource-contents"))
    contents = Array(Mcpc::ResourceContents).from_json(result["contents"].to_json)
    contents.first.uri.should start_with("file://")
    contents.first.text.should_not be_nil
  end

  it "reads binary resource contents" do
    name = Dir.children(FIXTURES / "BlobResourceContents").first.rchop(".json")
    Mcpc::ResourceContents.from_json(fixture("BlobResourceContents", name)).blob.should_not be_nil
  end

  it "reads a prompt result" do
    result = Mcpc::PromptResult.from_json(fixture("GetPromptResult", "code-review-prompt"))
    result.messages.first.role.should eq("user")
    result.messages.first.content.should be_a(Mcpc::TextContent)
  end

  it "reads every example of the list results" do
    {"ListToolsResult" => {"tools", Mcpc::Tool}, "ListPromptsResult" => {"prompts", Mcpc::Prompt}}.each do |type, (key, _)|
      Dir.glob((FIXTURES / type / "*.json").to_s).each do |path|
        JSON.parse(File.read(path))[key].as_a.should_not be_empty
      end
    end
    tools = JSON.parse(File.read(Dir.glob((FIXTURES / "ListToolsResult" / "*.json").to_s).first))["tools"]
    Array(Mcpc::Tool).from_json(tools.to_json).first.name.should_not be_empty
    prompts = JSON.parse(File.read(Dir.glob((FIXTURES / "ListPromptsResult" / "*.json").to_s).first))["prompts"]
    Array(Mcpc::Prompt).from_json(prompts.to_json).first.name.should_not be_empty
    resources = JSON.parse(File.read(Dir.glob((FIXTURES / "ListResourcesResult" / "*.json").to_s).first))["resources"]
    Array(Mcpc::Resource).from_json(resources.to_json).first.uri.should_not be_empty
    templates = JSON.parse(File.read(Dir.glob((FIXTURES / "ListResourceTemplatesResult" / "*.json").to_s).first))["resourceTemplates"]
    Array(Mcpc::ResourceTemplate).from_json(templates.to_json).first.uri_template.should_not be_empty
  end

  it "describes a server from a discover result" do
    result = JSON.parse(fixture("DiscoverResultResponse", "discover-result-response"))["result"]
    server = Mcpc::ServerInfo.from_discovery(result, "2026-07-28")
    server.implementation.try(&.name).should eq("ExampleServer")
    server.capabilities.tools?.should be_true
    server.capabilities.prompts?.should be_false
    server.stateless?.should be_true
  end

  it "reads the events carried by notification examples" do
    progress = Mcpc::JsonRpc.parse(fixture("ProgressNotification", "progress-message")).as(Mcpc::JsonRpc::Notification)
    Mcpc::NotificationEvents.translate(progress).should be_a(Mcpc::Event::Progress)

    name = Dir.children(FIXTURES / "LoggingMessageNotification").first.rchop(".json")
    log = Mcpc::JsonRpc.parse(fixture("LoggingMessageNotification", name)).as(Mcpc::JsonRpc::Notification)
    Mcpc::NotificationEvents.translate(log).should be_a(Mcpc::Event::LogMessage)

    name = Dir.children(FIXTURES / "ResourceUpdatedNotification").first.rchop(".json")
    updated = Mcpc::JsonRpc.parse(fixture("ResourceUpdatedNotification", name)).as(Mcpc::JsonRpc::Notification)
    Mcpc::NotificationEvents.translate(updated).should be_a(Mcpc::Event::ResourceUpdated)
  end

  it "has no event for a malformed or unknown notification" do
    malformed = Mcpc::JsonRpc::Notification.new("notifications/progress", JSON.parse(%({"progress":"lots"})))
    Mcpc::NotificationEvents.translate(malformed).should be_nil
    Mcpc::NotificationEvents.translate(Mcpc::JsonRpc::Notification.new("notifications/unheard_of")).should be_nil
  end
end
