# require 'pivotal_tracker'
# PIVOTAL_TRACKER_TOKEN = ENV.fetch('PIVOTAL_TOKEN', nil)
#
#
# PivotalTracker::Client.token = PIVOTAL_TRACKER_TOKEN
# PivotalTracker::Client.timeout = 1000
#
# PivotalTracker::Project.all.each do |project|
#   release_story = nil
#   project.stories.all.reverse.each do |story|
#     if story.story_type == 'release'
#       release_story = story
#       puts "Found deadline...#{story.id}, #{story.name}, #{story.description}, #{story.deadline}"
#     elsif story.current_state == 'started' || story.current_state == 'finished' || story.current_state == 'unstarted'
#       labels = story.labels
#       labels ||= ''
#       if release_story && release_story.deadline
#         due_date = "Due #{release_story.deadline.strftime("%m/%d")}"
#         if labels =~ /Due\s*[0-9]+\\s*\/\s*[0-9]+/i
#           labels.gsub!(/Due\s*[0-9]+\\s*\/\s*[0-9]+/i, due_date)
#         elsif labels !~ /Due\s*/
#           labels << ',' if labels !~ /^\s*$/
#           labels << due_date
#         end
#       end
#       puts "Found #{story.current_state}...#{story.id}, #{story.name}, #{story.owned_by}, #{labels}"
#      end
#   end
# end

require 'tracker_api'
PIVOTAL_TRACKER_TOKEN = ENV.fetch('PIVOTAL_TOKEN', nil)
client = TrackerApi::Client.new(token: PIVOTAL_TRACKER_TOKEN)
person_id = nil # TODO temp


def project_label(project, release_story)
  return nil unless release_story && release_story.deadline
  due_date = "due #{release_story.deadline.strftime("%m/%d")}"
  if project.labels.map(&:name) =~ /#{due_date}/
    project.labels.each do |label|
      return label if label.name =~ /#{due_date}/
    end
  else
    return TrackerApi::Resources::Label.new(name: due_date)
  end
end

client.projects.each do |project|
  project_label = nil
  project.stories.reverse.each do |story|
    if story.story_type == 'release'
      project_label = project_label(project, story)
      # puts "Found deadline...#{story.id}, #{story.name}, #{story.description}, #{story.deadline}"
    elsif %w{finished started rejected planned unstarted unscheduled}.include?(story.current_state)
      next if person_id && !story.owner_ids.include?(person_id)
      labels = story.labels
      if project_label
        labels ||= []
        if labels.map(&:name).join(',') =~ /due\s*[0-9]+\\s*\/\s*[0-9]+/i
          labels.delete_if {|l| l.name =~ /due\s*[0-9]+\\s*\/\s*[0-9]+/i }
        end
        labels << project_label
      end
      # Update labels by just story.save
      puts "Found #{story.current_state}...#{story.id}, #{story.name}, #{story.owner_ids}, #{labels.map(&:name)}"
     end
  end
end

