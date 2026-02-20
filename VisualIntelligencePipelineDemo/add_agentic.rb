require 'xcodeproj'
project_path = 'VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'VisualIntelligencePipeline' }
file_ref = project.files.find { |f| f.path =~ /AgenticChatView.swift/ }
if file_ref
  unless app_target.source_build_phase.files_references.include?(file_ref)
    app_target.source_build_phase.add_file_reference(file_ref)
    project.save
    puts "Added AgenticChatView.swift to app target"
  else
    puts "Already in app target"
  end
else
  puts "File ref not found!"
  
  # create it if it doesn't exist? No, we know it's in the repo.
  # Let's add the file ref manually.
  group = project.main_group.find_subpath('VisualIntelligencePipeline/View', true)
  new_file_ref = group.new_reference('AgenticChatView.swift')
  app_target.source_build_phase.add_file_reference(new_file_ref)
  project.save
  puts "Created file ref and added to app target"
end
