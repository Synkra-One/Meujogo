require "tempfile"

root = File.expand_path("..", __dir__)
files = {
  "FlashlightConfig" => "src/ReplicatedStorage/Modules/FlashlightConfig.lua",
  "FlashlightRules" => "src/ReplicatedStorage/Modules/FlashlightRules.lua",
  "FlashlightTargeting" => "src/server/FlashlightTargeting.lua",
  "FlashlightSystem" => "src/server/FlashlightSystem.lua",
  "DamageSystem" => "src/server/DamageSystem.lua"
}
Tempfile.create(["flashlight-tests", ".luau"]) do |file|
  file.write("local sources = {}\n")
  files.each do |name, path|
    source = File.read(File.join(root, path))
    separator = "="
    separator += "=" while source.include?("]#{separator}]")
    file.write("sources[#{name.dump}] = [#{separator}[#{source}]#{separator}]\n")
  end
  file.write(File.read(File.join(__dir__, "flashlight.luau")))
  file.flush
  exit(system(ARGV.fetch(0, "luau"), file.path) ? 0 : 1)
end
