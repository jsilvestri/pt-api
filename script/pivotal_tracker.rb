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


# Ideas:
# 1. admin page to see which stories you have and current status
# 2. update each story to have deadline labels that are accurate (run every 15 mins or so / continuous loop except at night to meet Heroku hobby needs)
# 3. same as #2, but update headline instead or description?

require 'tracker_api'
require 'active_support/core_ext'
PIVOTAL_TRACKER_TOKEN = ENV.fetch('PIVOTAL_TOKEN', nil)
client = TrackerApi::Client.new(token: PIVOTAL_TRACKER_TOKEN)
person_id = nil

def projects_with_activity(client, last_fetch)
  projects = []
  client.projects.each do |project|
    projects << project if project.activity(occurred_after: last_fetch.iso8601).size > 0
  end
  projects
end

def all_members(client)
  people = []
  client.projects.each do |project|
    people += project.memberships.map(&:person)
    # story_create
  end

  uniq_people = []
  people.each do |person|
    uniq_people << person unless uniq_people.map(&:id).include?(person.id)
  end

  uniq_people
end
# all_members(client).each do |person|
#   puts "#{person.id}: #{person.name}"
# end

def due_date(date)
  return nil unless date
  "due #{date.strftime("%a %m/%d").downcase}"
end

def project_label(project, due_date)
  return nil unless due_date
  if project.labels.map(&:name) =~ /#{due_date}/
    project.labels.each do |label|
      return label if label.name =~ /#{due_date}/
    end
  else
    return TrackerApi::Resources::Label.new(name: due_date)
  end
end

projects_with_activity(client, Time.now.advance(hours: -1)).each do |project|
  due_date = nil
  project_label = nil
  project.stories(filter: 'current_state:finished,started,rejected,planned,unstarted,unscheduled').reverse.each do |story|
    if story.story_type == 'release'
      due_date = due_date(story.deadline)
      project_label = project_label(project, due_date)
      # puts "Found deadline...#{story.id}, #{story.name}, #{story.description}, #{story.deadline}"
    elsif %w{finished started rejected planned unstarted unscheduled}.include?(story.current_state)
      next if person_id && !story.owner_ids.include?(person_id)
      labels = story.labels
      if project_label
        labels ||= []
        # Don't update if we already have due date there!
        next if labels.map(&:name).join(',') =~ /#{due_date}/i
        if labels.map(&:name).join(',') =~ /due\s*[0-9]+\\s*\/\s*[0-9]+/i
          labels.delete_if {|l| l.name =~ /due\s*[0-9]+\\s*\/\s*[0-9]+/i }
        end
        labels << project_label
      end
      # TODO Update labels by just story.save
      puts "Found #{story.current_state}...#{story.id}, #{story.name}, #{story.owner_ids}, #{labels.map(&:name)}"
     end
  end
end

