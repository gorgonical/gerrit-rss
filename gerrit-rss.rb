#/usr/bin/ruby

require 'atom'
require 'optparse'
require 'json'
require 'faraday'
require 'trollop'

class GerritRSS

  def initialize(feed_len, feed_file_path, gerrit_url, scores=Array.new)
    @feed_length = feed_len # Should be an integer
    @path_to_feeds = feed_file_path # Should be a string representing a UNIX file path
    @gerrit_api_url = gerrit_url # Should be a string representing a web URL
    @score_categories = scores # Should be an array of strings representing score categories.
                               # Defaults to an empty array, i.e. include no comment details.
  end

  def parse_options(command_line, program_name)
    parser = Trollop::Parser.new do
      opt :project, "Name of project", :type => :string
      opt :change, "Change ID of change", :type => :string
      opt :change_owner, "Owner of change", :type => :string
      opt :author, "Author of comment", :type => :string
      opt :comment, "Comment text", :type => :string
      opt :change_url, "URL of change on gerrit", :type => :string
      opt :Code_Review, "Code review category", :type => :integer
      opt :Verified, "Verified category", :type => :integer
      opt :Code_Style, "Code style category", :type => :integer
    end

    options = Trollop::with_standard_exception_handling(parser) do
      parser.ignore_invalid_options = true
      parser.parse(command_line)
    end

    # We only want the email of the change owner/author, but we get it
    # in a form like this: "<username> (<email>)"
    if options[:change_owner]
      options[:change_owner] = /.*\((.+@.+)\)/.match(options[:change_owner]).captures[0]
    end
    if options[:author]
      options[:author] = /.*\((.+@.+)\)/.match(options[:author]).captures[0]
    end

    # Get only the binary name off the end and provide that as an option.
    options[:program_name] = program_name.split('/')[-1]

    # Not only accept these arguments, but require them. Unless the
    # gerrit API changes, these must be included.
    if options[:project] == nil
      raise ArgumentError, "Project is missing", caller
    elsif options[:change] == nil
      raise ArgumentError, "ChangeID is missing", caller
    elsif options[:change_owner] == nil
      raise ArgumentError, "Owner is missing", caller
    elsif options[:change_url] == nil
      raise ArgumentError, "URL is missing", caller
    end
    options
  end

  def publish_to_feed_file(options)
    File.open(@path_to_feeds + "/" + options[:project] + ".rss", File::CREAT|File::RDWR, 0644) do |file|
      # Lock the file for writing. This should block until a lock can be
      # obtained. Then read the existing XML into a feed object.
      file.flock(File::LOCK_EX)
      # If the feed was initially empty, fill it with the bare feed skeleton.
      if File.zero?(file)
        file.write(initialize_feed(options).to_xml)
        file.flush
        file.truncate(file.pos)
        file.rewind
      end
      feed = Atom::Feed.load_feed(file)
      # The sequence number should be the next one in the list.
      options[:sequence_number] = feed.entries[0].id.to_i+1
      # Generate the RSS entry from the options and append to the feed
      feed.entries << generate_rss(options)
      # Truncate the feed entries array to the maximum length we set
      feed.entries = feed.entries[0 .. @feed_length-1]
      # Update the timestamp the feed was modified at
      feed.updated = Time.now

      # Rewind, write, flush, and close the file.
      file.rewind
      file.write(feed.to_xml)
      file.flush
      file.truncate(file.pos)
    end
  end

  def initialize_feed(options)
    Atom::Feed.new do |feed|
      feed.title = "#{options[:project]}"
      feed.links << @gerrit_api_url
      feed.updated = Time.now
      feed.id = options[:project]
      feed.entries << Atom::Entry.new do |entry|
        entry.id = 0
        entry.updated = Time.now
        entry.title = "Initial entry"
        entry.summary = "Initial entry for this project"
      end
    end
  end

  # Given a hash of options, return an Atom::Entry object
  def generate_rss(options)
    Atom::Entry.new do |entry|
      # These three fields are always the same
      entry.links << options[:change_url]
      entry.id = options[:sequence_number].to_s + ":" + options[:change] # So services have the change id, too
      entry.updated = Time.now
      # The entry needs to be different depending on how this script was
      # called
      case options[:program_name]
      when "patchset-created"
        entry.title = "patchset-created: New patch set from #{options[:change_owner]}"
        entry.summary = "New patch set from #{options[:change_owner]} for change: \"#{options[:subject]}\""
      when "comment-added"
        # Include switches for the comment category and score
        entry.title = "comment-added: New comment added for: \"#{options[:subject]}\""
        entry.summary = "New comment from #{options[:author]} for change: \"#{options[:subject]}\""
        entry.content = "Comments:"
        # Iterate over each category we are configured to export
        @score_categories.each do |category_string|
          entry.content = entry.content + "\n" + \
                          category_string + ":" + options[category_string.to_sym].to_s \
                          if options[category_string.to_sym]
        end
      else
        entry.title = "other-change: A change has happened for: \"#{options[:subject]}\""
        entry.summary = "Something has happened for change: \"#{options[:subject]}\""
      end
    end
  end

  # Returns a hash of the basic change details of the change with change_id as its ID.
  def fetch_change(change_id)
    JSON.parse(Faraday.get(@gerrit_api_url + "/changes/#{change_id}").body.lines.drop(1).join)
  end

end
