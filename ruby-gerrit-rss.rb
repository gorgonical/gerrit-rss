# maintain a different RSS feed for each project
## this is in the gerrit hook command line arguments
# lock the RSS file, read it in somehow
# boot out the oldest entry
# put in the newer entry
# write back to RSS
# delete lock file

require 'atom'
require 'optparse'
require 'json'
require 'faraday'

feed_length = 50
path_to_feeds = "/some/path"
gerrit_api_url = "https://gerrit.named-data.net"

options = {}
OptionParser.new do |options|
  options = OpenStruct.new
  options.project = nil
  options.change_id = nil
  options.owner = nil
  options.author = nil
  options.comment = nil
  options.change_url = nil

  opts.on("--project PROJECT") do |p|
    options.project = p
  end

  opts.on("--change CHANGEID") do |c|
    options.change_id = c
  end

  opts.on("--change-owner OWNER") do |o|
    options.owner = o
  end

  opts.on("--author [AUTHOR]") do |a|
    options.author = a
  end

  opts.on("--comment [COMMENT]") do |c|
    options.comment = c
  end

  opts.on("--change-url URL") do |u|
    options.change_url = u
  end
end

# Go ahead and get some information about the change now
change_info = fetch_change(change_id)

feed_file = File.open("/path/to/gerrit/feeds/#{options[project]}.rss", "r+") do |file|
  # Lock the file for writing. This should block until a lock can be
  # obtained. Then read the existing XML into a feed object.
  file.flock(File::LOCK_EX)
  feed = Atom::Feed.load_feed(file)
  feed.entries << Atom::Entry.new do |entry|
    # These three fields are always the same
    entry.links << options[change_url]
    entry.id = options[change_id]
    entry.update = Time.now
    # The entry needs to be different depending on how this script was
    # called
    case $0
    when "draft-published"
      entry.title = "New patch set from #{options[owner]}"
      entry.summary = "New patch set from #{options[owner]} for change #{change_info[subject]}"
    when "comment-added"
      entry.title = "New comment added for \"#{change_info[subject]}\""
      entry.summary = "A new comment from #{options[author]} for change #{change_info[subject]}"
    else
      entry.title = "A change has happened for: #{change_info[subject]}"
      entry.summary = "Something has happende for: #{change_info[subject]}"
    end
  end

  # Truncate the feed entries array to the maximum length we set
  feed.entries = feed.entries[0 .. feed_length]
  # Rewind, write, flush, and close the file.
  file.rewind
  file.write(feed.to_xml)
  file.flush
  file.truncate(file.pos)
end

def fetch_change(change_id)
  return JSON.parse(Faraday.get(gerrit_api_url + "changes/#{change_id}").body.lines.drop(1).join)
end
