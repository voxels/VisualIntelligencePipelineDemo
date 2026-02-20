require 'xcodeproj'
project_path = 'VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj'
project = Xcodeproj::Project.open(project_path)
widget_target = project.targets.find { |t| t.name == 'VisualIntelligencePipelineWidget' }
file_ref = project.files.find { |f| f.path =~ /AskCLaRaIntent.swift/ }
if file_ref && widget_target
  unless widget_target.source_build_phase.files_references.include?(file_ref)
    widget_target.source_build_phase.add_file_reference(file_ref)
    project.save
    puts "Added to widget target"
  else
    puts "Already in widget target"
  end
else
  puts "Target or file missing"
end
