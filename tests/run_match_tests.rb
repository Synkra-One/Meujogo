require "tempfile"
require "rexml/document"

root = File.expand_path("..", __dir__)
sources = %w[RoleAssignment RoundManager WaitingRoomManager].to_h do |name|
  [name, File.read(File.join(root, "src/server/#{name}.lua"))]
end
xml = REXML::Document.new(File.read(File.join(root, "src/MovementPack/ServerScriptService/DeathRespawnHandler.rbxmx")))
sources["DeathRespawnHandler"] = REXML::XPath.first(xml, "//string[@name='Source']").text

Tempfile.create(["match-tests", ".luau"]) do |file|
  file.write("local sources = {}\n")
  sources.each do |name, source|
    separator = "="
    separator += "=" while source.include?("]#{separator}]")
    file.write("sources[#{name.dump}] = [#{separator}[#{source}]#{separator}]\n")
  end
  file.write(File.read(File.join(__dir__, "MatchLifecycle.spec.luau")))
  file.flush
  exit(system(ARGV.fetch(0, "luau"), file.path) ? 0 : 1)
end
