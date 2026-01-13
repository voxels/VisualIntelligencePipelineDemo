#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'VisualIntelligencePipelineDemo/VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Set global version/build
marketing_version = "1.0"
current_project_version = "2" # Incrementing to 2 for Beta 1

puts "Bumping version to #{marketing_version} (Build #{current_project_version})..."

project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['MARKETING_VERSION'] = marketing_version
    config.build_settings['CURRENT_PROJECT_VERSION'] = current_project_version
    puts "  Updated #{target.name} (#{config.name})"
  end
end

project.save
puts "Project saved!"
