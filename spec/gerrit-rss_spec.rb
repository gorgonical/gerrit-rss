require_relative '../gerrit-rss.rb'

RSpec.describe GerritRSS do

  it "requires three initialization arguments" do
    expect { GerritRSS.new("a", "b") }.to raise_error(ArgumentError)
  end

  context "when parsing command-line arguments (.parse_options)" do
    it "requires --project to be specified" do
      test_args = ["--notproject", "abc123"]
      expect { GerritRSS.new(50, "/path", "http://test.com").parse_options(test_args, "name") }.to raise_error(ArgumentError)
    end

    it "requires --change to be specified" do
      test_args = ["--project", "abc123"]
      expect { GerritRSS.new(50, "/path", "http://test.com").parse_options(test_args, "name") }.to raise_error(ArgumentError)
    end

    it "requires --change-owner to be specified" do
      test_args = ["--project", "abc123", "--change", "1000", "--notowner", "user (someone@somewhere.com)"]
      expect { GerritRSS.new(50, "/path", "http://test.com").parse_options(test_args, "name") }.to raise_error(ArgumentError)
    end

    it "requires --change-url to be specified" do
      test_args = ["--project", "abc123", "--change", "1000", "--notowner", "user (someone@somewhere.com)", "--notchange_url", "https://somewhere.com/someid"]

      expect { GerritRSS.new(50, "/path", "http://test.com").parse_options(test_args, "name") }.to raise_error(ArgumentError)
    end

    it "provides --project, --change, --change-owner, and --change-url" do
      test_args = ["--project", "abc123", "--change", "1000", "--change-owner", "user (someone@somewhere.com)", "--change-url", "https://somewhere.com/someid"]
      options = GerritRSS.new(50, "/path", "http://test.com").parse_options(test_args, "name")
      expect(options[:project]).to eq("abc123")
      expect(options[:change]).to eq("1000")
      expect(options[:change_owner]).to eq("someone@somewhere.com")
      expect(options[:change_url]).to eq("https://somewhere.com/someid")
    end

    it "provides the calling program name as a variable" do
      test_args = ["--project", "abc123", "--change", "1000", "--change-owner", "user (someone@somewhere.com)", "--change-url", "https://somewhere.com/someid"]
      options = GerritRSS.new(50, "/path", "http://test.com").parse_options(test_args, "name")
      expect(options[:program_name]).to eq("name")
    end

    it "accepts if --author is specified" do
      test_args = ["--project", "abc123", "--change", "1000", "--change-owner", "user (someone@somewhere.com)", "--change-url", "https://somewhere.com/someid", "--author", "guy (guy@place.com)"]
      options = GerritRSS.new(50, "/path", "http://test.com").parse_options(test_args, "name")
      expect(options[:author]).to eq("guy@place.com")
    end

    it "accepts if --comment is specified" do
      test_args = ["--project", "abc123", "--change", "1000", "--change-owner", "user (someone@somewhere.com)", "--change-url", "https://somewhere.com/someid", "--comment", "Test comment"]
      options = GerritRSS.new(50, "/path", "http://test.com").parse_options(test_args, "name")
      expect(options[:comment]).to eq("Test comment")
    end
  end

  context "when generating RSS (.generate_rss)" do
    it "returns an entry with title, summary, links, id, and update set" do
      test_options = {:change_url => "http://test.com", :change => "someid",
                      :program_name => "other_program", :subject => "test subject"}
      entry = GerritRSS.new(50, "/path", "http://test.com").generate_rss(test_options)
      expect(entry.title).to eq("A change has happened for: \"test subject\"")
      expect(entry.summary).to eq("Something has happened for change: \"test subject\"")
      testLinks = Atom::Links.new
      testLinks << "http://test.com"
      expect(entry.links).to eq(testLinks)
      expect(entry.id).to eq("someid")
      expect(entry.updated).to be_within(2).of(Time.now.utc())
    end

    context "when $0 is \"patchset-created\"" do
      it "returns a default entry, but with a specific title and summary" do
        test_options = {:change_url => "http://test.com", :change => "someid",
                        :program_name => "patchset-created", :subject => "test subject",
                        :change_owner => "guy@place.com"}
        entry = GerritRSS.new(50, "/path", "http://test.com").generate_rss(test_options)
        expect(entry.title).to eq("New patch set from guy@place.com")
        expect(entry.summary).to eq("New patch set from guy@place.com for change: \"test subject\"")
      end
    end

    context "when $0 is \"comment-added\"" do
      it "returns a default entry, but with a specific title and summary" do
        test_options = {:change_url => "http://test.com", :change => "someid",
                        :program_name => "comment-added", :subject => "test subject",
                        :author => "commenter@place.com"}
        entry = GerritRSS.new(50, "/path", "http://test.com").generate_rss(test_options)
        expect(entry.title).to eq("New comment added for: \"test subject\"")
        expect(entry.summary).to eq("New comment from commenter@place.com for change: \"test subject\"")
      end
    end
  end

  context "when publishing the feed to the file on the server" do

    num_entries = 50
    project_name = "testProject"
    test_options = {:change_url => "http://test.com", :change => "someid",
                    :program_name => "other_program", :subject => "test subject",
                    :project => project_name}
    rss_feed = GerritRSS.new(num_entries, ".", "http://test.com")

    it "creates an empty feed if the feed file is missing" do
      # Ensure that we have a clean workspace first
      if File.exist?("./testProject.rss")
        File.delete("./testProject.rss")
      end
      rss_feed.publish_to_feed_file(test_options)
      expect{Atom::Feed.load_feed(File.open("./testProject.rss"))}.not_to raise_error
    end

    it "ensures that the RSS feed is no more than @feed_length in size" do


      ####################
      # As a remark, there has got to be a better way to do this
      # test. This IO mocking is just unbelievably kludgy.
      ####################

      # num_entries = 50
      # project_name = "testProject"
      # test_options = {:change_url => "http://test.com", :change => "someid",
      #                 :program_name => "other_program", :subject => "test subject",
      #                 :project => project_name}
      # rss_feed = GerritRSS.new(num_entries, ".", "http://test.com")

      # Entry content
      entry = <<-EOF
<entry>
  <title>Test title</title>
  <id>1234</id>
  <summary>Test summary</summary>
  <updated>2017-05-08T11:18:41-05:00</updated>
  <link>http://test.com</link>
</entry>
EOF

      # Build a max-length feed.
      feed = String.new
      feed << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      feed << "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
      num_entries.times { feed << entry }
      feed << "</feed>\n"

      # Write what we're expecting out to the file: a feed with 50 entries already.
      file_IO = File.new("./testProject.rss", File::CREAT|File::TRUNC|File::RDWR, 0644)
      file_IO.rewind
      file_IO.write(feed)
      file_IO.flush
      file_IO.truncate(file_IO.pos)

      # Publish a new entry and truncate it to the specified length
      rss_feed.publish_to_feed_file(test_options)

      # Re-load the feed and examine its length to ensure it's still
      # only 50. Also check that the first entry has the modified id,
      # and was actually written.
      modified_feed = Atom::Feed.load_feed(File.open("./testProject.rss"))
      expect(modified_feed.entries.size).to eq(num_entries)
      expect(modified_feed.entries.first.id).to eq("1234")
    end
  end
end
