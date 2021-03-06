require 'rake'
require 'tracker_api'
require 'active_support/core_ext'

# This contains some default tasks to use with heroku test applications
namespace :pivotal do
  DUE_REGEX = 'due [^0-9]*?\s*[0-9]+\\s*\/\s*[0-9]+'

  desc 'Set due dates on all active projects and stories.
         LIVE=true if running code rather than testing output.
         ALL=true if first run in a while, DAY=true for all recent updates in last day'
  task set_due_dates: :environment do
    test_mode = true unless ENV.fetch('LIVE', false)
    token = ENV.fetch('PIVOTAL_TOKEN', nil)
    client = TrackerApi::Client.new(token: token)
    labels_endpoint = TrackerApi::Endpoints::Labels.new(client)
    if ENV['ALL']
      projects = client.projects
    elsif ENV['DAY']
      projects = _projects_with_activity(client, Time.now.advance(hours: -26))
    else
      projects = _projects_with_activity(client, Time.now.advance(minutes: -31))
    end

    projects.each do |project|
      due_date = nil
      project_label = nil
      project_states = %w{delivered finished started rejected planned unstarted unscheduled}
      project_states_query =
        'current_state:delivered,finished,started,rejected,planned,unstarted,unscheduled'
      project.stories(filter: project_states_query).reverse.each do |story|
        do_something = false
        if story.story_type == 'release'
          due_date = _due_date(story)
          project_label = _project_label(project, due_date)
        elsif project_states.include?(story.current_state)
          labels = story.labels
          if project_label
            labels ||= []
            # Don't update if we already have due date there!
            next if labels.map(&:name).join(',') =~ /#{due_date}/i
            if labels.map(&:name).join(',') =~ /#{DUE_REGEX}/i
              labels.each do |label|
                if label.name =~ /#{DUE_REGEX}/i
                  do_something = true
                  # This line deletes the label safely (ie no updating the rest of the story)
                  if test_mode
                    puts '--------soft delete ' + label.name
                  else
                    labels_endpoint.delete_from_story(project.id, story.id, label.id)
                    Rails.logger.warn "Deleted #{label.name} from #{project.id}/#{story.id}"
                  end
                end
              end
            end
            # This line actually adds the label safely (ie no updating the rest of the story)
            do_something = true
            if test_mode
              puts '--------soft add ' + due_date
            else
              labels_endpoint.add_to_story(project.id, story.id, {name: due_date})
              Rails.logger.warn "Added #{due_date} to #{project.id}/#{story.id}"
            end
          else
            # Remove deadline label if there is no longer a deadline
            labels ||= []
            # Don't update if we don't already have a due date there!
            next if labels.map(&:name).join(',') !~ /#{DUE_REGEX}/i
            labels.each do |label|
              if label.name =~ /#{DUE_REGEX}/i
                do_something = true
                # This line deletes the label safely (ie no updating the rest of the story)
                if test_mode
                  puts '--------soft remove (no longer due date) ' + label.name
                else
                  labels_endpoint.delete_from_story(project.id, story.id, label.id)
                  Rails.logger.warn "Removed #{label.name} from #{project.id}/#{story.id}"
                end
              end
            end
          end
          if test_mode
            str = "Found #{story.current_state}...#{story.id}, #{story.name}, #{story.owner_ids},
                    #{labels.map(&:name)}, do something? #{do_something}"
            puts str
            Rails.logger.warn str
          end
        end
      end
    end
  end

  desc 'Remove due dates on all active projects and stories
        LIVE=true if running code rather than testing output.'
  task remove_due_dates: :environment do
    test_mode = true unless ENV.fetch('LIVE', false)
    token = ENV.fetch('PIVOTAL_TOKEN', nil)
    client = TrackerApi::Client.new(token: token)
    project_states = %w{delivered finished started rejected planned unstarted unscheduled}
    project_states_query =
      'current_state:delivered,finished,started,rejected,planned,unstarted,unscheduled'

    client.projects.each do |project|
      project.stories(filter: project_states_query).reverse.each do |story|
        do_something = false
        if story.story_type != 'release' && project_states.include?(story.current_state)
          labels = story.labels
          labels ||= []
          if labels.map(&:name).join(',') =~ /#{DUE_REGEX}/i
            labels.each do |label|
              if label.name =~ /#{DUE_REGEX}/i
                do_something = true
                # This line deletes the label safely (ie no updating the rest of the story)
                if test_mode
                  puts '--------soft delete ' + label.name
                else
                  labels_endpoint.delete_from_story(project.id, story.id, label.id)
                  Rails.logger.warn "Deleted #{label.name} from #{project.id}/#{story.id}"
                end
              end
            end
          end
          if test_mode
            str = "Found #{story.current_state}...#{story.id}, #{story.name},
                    #{story.owner_ids}, #{labels.map(&:name)}, do something? #{do_something}"
            puts str
            Rails.logger.warn str
          end
        end
      end
    end
  end

  private

  def _projects_with_activity(client, last_fetch)
    projects = []
    client.projects.each do |project|
      projects << project if project.activity(occurred_after: last_fetch.iso8601).size > 0
    end
    projects
  end

  def _due_date(story)
    if story.name =~ /\(\s?(EOD)?\s?([0-9]+)\s?\/\s?([0-9]+)\s?(EOD)?\s?\)/
      # Frances started putting deadlines in parens in the story name
      # rather than in the deadline field.  e.g. (8/3 EOD)
      month = $2
      day = $3
      year = Date.today.strftime("%Y")
      today_month = Date.today.strftime("%-m")
      # Assume we are not > 2 months behind a deadline or setting deadlines > 8 months out!
      # We need this to display the day of week correctly
      if month.to_i + 3 < today_month.to_i
        year = year.to_i + 1
      end
      deadline = Date.parse("#{day}-#{month}-#{year}")
    elsif
      story.deadline
      deadline = story.deadline
    else
      return nil # No date!
    end

    "due #{deadline.strftime("%a %-m/%-d").downcase}"
  end

  def _project_label(project, due_date)
    return nil unless due_date
    if project.labels.map(&:name) =~ /#{due_date}/
      project.labels.each do |label|
        return label if label.name =~ /#{due_date}/
      end
    else
      return TrackerApi::Resources::Label.new(name: due_date)
    end
  end
end
