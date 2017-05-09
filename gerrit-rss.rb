#/usr/bin/env ruby
require 'atom'
require 'optparse'
require 'json'
require 'faraday'

class GerritRSS

  def initialize(feed_len, feed_file_path, gerrit_url)
    @feed_length = feed_len
    @path_to_feeds = feed_file_path
    @gerrit_api_url = gerrit_url
  end

  def parse_options(command_line, program_name)
    options = {}
    OptionParser.new do |opts|
      opts.banner = "test!"
      options = OpenStruct.new
      options[:project] = nil
      options[:change_id] = nil
      options[:owner] = nil
      options[:author] = nil
      options[:comment] = nil
      options[:change_url] = nil
      options[:program_name] = program_name

      opts.on('-p', '--project PROJECT', String, "Name of project") do |p|
        options[:project] = p
      end

      opts.on('-c', '--change CHANGEID', String, "ChangeID of change") do |c|
        options[:change_id] = c
      end

      opts.on('-w', '--change-owner OWNER', String, "Owner of change") do |o|
        options[:owner] = o
      end

      opts.on('-a', '--author [AUTHOR]', String, "Author of comment") do |a|
        options[:author] = a
      end

      opts.on('-m', '--comment [COMMENT]', String, "Text of comment") do |c|
        options[:comment] = c
      end

      opts.on('-u', '--change-url URL', String, "URL of change on gerrit") do |u|
        options[:change_url] = u
      end
    end.parse(command_line)
    # Not only accept these arguments, but require them. Unless the
    # gerrit API changes, these must be included.
    if options[:project] == nil
      raise ArgumentError, "Project is missing", caller
    elsif options[:change_id] == nil
      raise ArgumentError, "ChangeID is missing", caller
    elsif options[:owner] == nil
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
      feed = Atom::Feed.load_feed(file)

      # Generate the RSS entry from the options and append to the feed
      feed.entries << generate_rss(options)
      # Truncate the feed entries array to the maximum length we set
      feed.entries = feed.entries[0 .. @feed_length-1]

      # Rewind, write, flush, and close the file.
      file.rewind
      file.write(feed.to_xml)
      file.flush
      file.truncate(file.pos)
    end
  end

  def generate_rss(options)
    Atom::Entry.new do |entry|
      # These three fields are always the same
      entry.links << options[:change_url]
      entry.id = options[:change_id]
      entry.updated = Time.now
      # The entry needs to be different depending on how this script was
      # called
      case options[:program_name]
          
      when "draft-published"
        entry.title = "New patch set from #{options[:owner]}"
        entry.summary = "New patch set from #{options[:owner]} for change: \"#{options[:subject]}\""
      when "comment-added"
        entry.title = "New comment added for: \"#{options[:subject]}\""
        entry.summary = "New comment from #{options[:author]} for change: \"#{options[:subject]}\""
      else
        entry.title = "A change has happened for: \"#{options[:subject]}\""
        entry.summary = "Something has happened for change: \"#{options[:subject]}\""
      end
    end
  end

  # Returns a hash of the basic change details of the change with change_id as its ID.
  def fetch_change(change_id)
    JSON.parse(Faraday.get(@gerrit_api_url + "/changes/#{change_id}").body.lines.drop(1).join)
  end

end
