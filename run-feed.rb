#!/usr/bin/ruby
require_relative './gerrit-rss.rb'

# Get an instance of the publisher.
publisher = GerritRSS.new(50, "/path/to/feeds", "https://gerrit.named-data.net")

# Parse the options using the publisher.
options = publisher.parse_options(ARGV, $0)

# Fetch a little more information about the patch and add it to our information array.
change_info = publisher.fetch_change(options[:change_id])
options[:subject] = change_info["subject"]

# Publish the update
publisher.publish_to_feed_file(options)
