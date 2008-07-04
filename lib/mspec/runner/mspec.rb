require 'mspec/runner/state'
require 'mspec/runner/tag'
require 'fileutils'

module MSpec

  @exit    = nil
  @start   = nil
  @enter   = nil
  @before  = nil
  @after   = nil
  @leave   = nil
  @finish  = nil
  @exclude = nil
  @include = nil
  @leave   = nil
  @mode    = nil
  @load    = nil
  @unload  = nil
  @randomize   = nil
  @expectation = nil

  def self.describe(mod, msg=nil, &block)
    stack.push RunState.new

    current.describe(mod, msg, &block)
    current.process

    stack.pop
  end

  def self.process
    actions :start
    files
    actions :finish
  end

  def self.files
    return unless files = retrieve(:files)

    shuffle files if randomize?
    files.each do |file|
      @env = Object.new
      @env.extend MSpec

      store :file, file
      actions :load
      protect("loading #{file}") { Kernel.load file }
      actions :unload
    end
  end

  def self.actions(action, *args)
    actions = retrieve(action)
    actions.each { |obj| obj.send action, *args } if actions
  end

  def self.register_exit(code)
    store :exit, code
  end

  def self.exit_code
    retrieve(:exit).to_i
  end

  def self.register_files(files)
    store :files, files
  end

  # Stores one or more substitution patterns for transforming
  # a spec filename into a tags filename, where each pattern
  # has the form:
  #
  #   [Regexp, String]
  #
  # See also +tags_file+.
  def self.register_tags_patterns(patterns)
    store :tags_patterns, patterns
  end

  def self.register_mode(mode)
    store :mode, mode
  end

  def self.retrieve(symbol)
    instance_variable_get :"@#{symbol}"
  end

  def self.store(symbol, value)
    instance_variable_set :"@#{symbol}", value
  end

  # This method is used for registering actions that are
  # run at particular points in the spec cycle:
  #   :start        before any specs are run
  #   :load         before a spec file is loaded
  #   :enter        before a describe block is run
  #   :before       before a single spec is run
  #   :expectation  before a 'should', 'should_receive', etc.
  #   :after        after a single spec is run
  #   :leave        after a describe block is run
  #   :unload       after a spec file is run
  #   :finish       after all specs are run
  #
  # Objects registered as actions above should respond to
  # a method of the same name. For example, if an object
  # is registered as a :start action, it should respond to
  # a #start method call.
  #
  # Additionally, there are two "action" lists for
  # filtering specs:
  #   :include  return true if the spec should be run
  #   :exclude  return true if the spec should NOT be run
  #
  def self.register(symbol, action)
    unless value = retrieve(symbol)
      value = store symbol, []
    end
    value << action unless value.include? action
  end

  def self.unregister(symbol, action)
    if value = retrieve(symbol)
      value.delete action
    end
  end

  def self.protect(msg, &block)
    begin
      @env.instance_eval(&block)
    rescue Exception => e
      register_exit 1
      if current and current.state
        current.state.exceptions << [msg, e]
      elsif !$quiet_runner
        STDERR.write "\nAn exception occurred in #{msg}:\n#{e.class}: #{e.message.inspect}\n"
        STDERR.write "#{e.backtrace.join "\n"}"
      end
    end
  end

  def self.stack
    @stack ||= []
  end

  def self.current
    stack.last
  end

  def self.verify_mode?
    @mode == :verify
  end

  def self.report_mode?
    @mode == :report
  end

  def self.pretend_mode?
    @mode == :pretend
  end

  def self.randomize(flag=true)
    @randomize = flag
  end

  def self.randomize?
    @randomize == true
  end

  def self.shuffle(ary)
    return if ary.empty?

    size = ary.size
    size.times do |i|
      r = rand(size - i - 1)
      ary[i], ary[r] = ary[r], ary[i]
    end
  end

  # Transforms a spec filename into a tags filename by applying each
  # substitution pattern in :tags_pattern. The default patterns are:
  #
  #   [%r(/spec/), '/spec/tags/'], [/_spec.rb$/, '_tags.txt']
  #
  # which will perform the following transformation:
  #
  #   path/to/spec/class/method_spec.rb => path/to/spec/tags/class/method_tags.txt
  #
  # See also +register_tags_patterns+.
  def self.tags_file
    patterns = retrieve(:tags_patterns) ||
               [[%r(spec/), 'spec/tags/'], [/_spec.rb$/, '_tags.txt']]
    patterns.inject(retrieve(:file).dup) do |file, pattern|
      file.gsub(*pattern)
    end
  end

  def self.read_tags(*keys)
    tags = []
    file = tags_file
    if File.exist? file
      File.open(file, "r") do |f|
        f.each_line do |line|
          tag = SpecTag.new line.chomp
          tags << tag if keys.include? tag.tag
        end
      end
    end
    tags
  end

  def self.write_tag(tag)
    string = tag.to_s
    file = tags_file
    path = File.dirname file
    FileUtils.mkdir_p(path) unless File.exist?(path)
    if File.exist? file
      File.open(file, "r") do |f|
        f.each_line { |line| return false if line.chomp == string }
      end
    end
    File.open(file, "a") { |f| f.puts string }
    return true
  end

  def self.delete_tag(tag)
    deleted = false
    pattern = /#{tag.tag}.*#{Regexp.escape tag.description}/
    file = tags_file
    if File.exist? file
      lines = IO.readlines(file)
      File.open(file, "w") do |f|
        lines.each do |line|
          unless pattern =~ line.chomp
            f.puts line
          else
            deleted = true
          end
        end
      end
      File.delete file unless File.size? file
    end
    return deleted
  end
end
