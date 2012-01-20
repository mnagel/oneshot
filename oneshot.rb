#!/usr/bin/env ruby

#=begin
#    oneshot - simple(?) file uploader
#    Copyright (C) 2008, 2009, 2010, 2011, 2012 by Michael Nagel
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#=end

require 'digest/sha1'
require 'time'
require 'date'

# log messages have a level, that decides if they will be printed
LOG_ERROR  = -1
LOG_OUTPUT =  0
LOG_INFO   =  1
LOG_DEBUG  =  2

# string denoting the current version
THEVERSION = "oneshot 2011-03-28, licenced under GPLv3+"
# string denoting the date format to be used
DATEFORMAT = "%Y-%m-%d %H:%M:%S"

# reopen the Float class to add some functionality
class Float
  alias_method :orig_to_s, :to_s

  # easier formatted printing, using sprtintf...
  def to_s(arg = nil)
    if arg.nil?
      orig_to_s
    else
      sprintf("%.#{arg}f", self)
    end
  end
end

class String
  # return this string in qoutes
  def quote
    return '"' + self + '"'
  end

  # copied from file lib/shellwords.rb, line 69
  # escapes a string according to sh rules
  def shellescape str = self
    return "''" if str.nil? # added by nailor
    # An empty argument will be skipped, so return empty quotes.
    return "''" if str.empty?

    str = str.dup

    # Process as a single byte sequence because not all shell
    # implementations are multibyte aware.
    str.gsub!(/([^A-Za-z0-9_\-.,:\/@\n])/n, "\\\\\\1")

    # A LF cannot be escaped with a backslash because a backslash + LF
    # combo is regarded as line continuation and simply ignored.
    str.gsub!(/\n/, "'\n'")

    return str
  end

  def asciify
    return self.tr("^A-Za-z0-9_.\-", "_")
  end
end

class Exception
  def show
    STDERR.puts "there was an error: #{self.message}"
    STDERR.puts self.backtrace
    STDERR.puts "(invoked as $PROG #{ARGV.join(' ')})"
  end
end

def hashsum filename
  bufferlength = 1024
  hash = Digest::SHA1.new

  open(filename, "r") do |io|
    while (!io.eof)
      readBuf = io.readpartial(bufferlength)
      hash.update(readBuf)
    end
  end
  return hash.hexdigest
end

# send a string to the logging system, with according log level
def log string, loglevel
  puts string unless @options.verbosity < loglevel
end

# send a string to the logging system, with according log level
def log_bad_encapsulation string, loglevel # FIXME drop this function and fix the one above
  puts string #unless @options.verbosity < loglevel
end

class Thumbnails

  def self.dim imgpath
    cmd = "identify -format '%w' #{imgpath.shellescape}"
    w = %x(#{cmd}).to_i

    cmd = "identify -format '%h' #{imgpath.shellescape}"
    h = %x(#{cmd}).to_i
    return w, h
  end

  def self.create path_input, path_output
    if path_input.match(/\//) || !File.exists?(path_input)
      log_bad_encapsulation "cannot create thumbnail: file #{path_input} does not exist.", LOG_ERROR
      exit(-1)
    end

    cmd = "convert -thumbnail 'x128' #{path_input.shellescape} #{path_output.shellescape}"
    w = %x(#{cmd})
  end

  def initialize
    @enabled = false
    @mytrans = []
  end

  def enable
    @enabled = true
  end

  def add_file transfer
    return unless @enabled
    localpath = transfer.path_local(false)
    Thumbnails.create(localpath, Thumbnails.local_thumb_path(localpath))
    @mytrans << Transfer.new(Thumbnails.local_thumb_path(localpath), Thumbnails.local_thumb_name(localpath), "internal thumbnail", "no url")
  end

  def get_my_transfers
    return [] unless @enabled
    return @mytrans
  end

  def self.local_thumb_name local_name
  	  return local_name.asciify + ".thumb.jpg"
  end

  def self.local_thumb_path local_name
  	  return "/tmp/oneshot-#{Thumbnails.local_thumb_name(local_name)}"
  end

  def index_thumb_url transfer, defaultthumb
    return defaultthumb unless @enabled
    return Thumbnails.local_thumb_name(transfer.path_local(false))
  end

  def index_thumb_width transfer, defaultsize
    return defaultsize unless @enabled
    tpath = Thumbnails.local_thumb_path(transfer.path_local(false))

    w,h = Thumbnails.dim(tpath)
    return w
  end

end

# build a string of defined length
# pre  : prefix
# char : char to be repeated
# post : postfix
# len  : length of final string, ignored if less then pre+post
def pad pre, char, post, len
  pre = '' if pre.nil?
  post = '' if post.nil?
  return pre + char * [len - pre.length - post.length, 0].max + post
end

# get a nice name (incl. path) for a temporary file
def tempfilename
  hsh = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..7)
  return "/tmp/oneshot-#{hsh}.htm"
end

# check if directory is empty
def emptydir? dirname
  return Dir.entries(dirname).size == 2
end

# remove a folder if it is empty
def cleanup dir
  if emptydir? dir
    system "rmdir " + dir
    log "cleaned empty folder " + dir, LOG_OUTPUT
  end
end

def serverside_check val
  begin
    dfs = Dir.new(val).sort {|a,b| a.to_s <=> b.to_s}
    dfs.each { |datefolder|
      next if ['.', '..'].include?(datefolder)
      datefolder = File.join(val, datefolder)
      log datefolder, LOG_DEBUG

      tfs = Dir.new(datefolder).sort {|a,b| a.to_s <=> b.to_s}
      tfs.each { |titlefolder|
        next if ['.', '..'].include?(titlefolder)
        titlefolder = File.join(datefolder, titlefolder)
        log titlefolder, LOG_DEBUG

        hfs = Dir.new(titlefolder).sort {|a,b| a.to_s <=> b.to_s}
        hfs.each { |hashfolder|
          next if ['.', '..'].include?(hashfolder)
          hashfolder = File.join(titlefolder, hashfolder)
          log hashfolder, LOG_DEBUG

          path = hashfolder + "/.oneshot-expiry"
          log "scanning " + path, LOG_DEBUG

          begin
            file = File.new(path, "r")
            date = file.gets
            log "best before: " + date, LOG_DEBUG

            date = Date.strptime(date, DATEFORMAT)
            ttl = (datify(Time.now) - date).to_i
            if ttl > 0
              log '! ' + hashfolder + ' has expired ' + ttl.to_s + ' days ago', LOG_OUTPUT
              command = "rm -r " + File.expand_path(hashfolder)
              puts "want to execute ' " + command + "'? [yY/$NUMDAYS/nN*]"
              #puts $stdin.gets.chomp

              ans = $stdin.gets.chomp
              if ['y','Y'].include?(ans)
                system command
              elsif ans.to_i != 0
                expiry = Time.now + ans.to_i * 60 * 60 * 24

                File.open(path, 'w+') { |f| f.puts expiry.strftime(DATEFORMAT) }
                log "new expiry: " + expiry.strftime(DATEFORMAT), LOG_OUTPUT
              end

            else
              log hashfolder + ' is valid for another ' + (- ttl).to_s + ' days', LOG_INFO
            end

          rescue => exc
            log "error opening " + path, LOG_ERROR
            exc.show
          end
        }

        cleanup titlefolder
      }
      cleanup datefolder
    }

  rescue => exc
    log "error scanning for outdated files. are you scanning a oneshot repo?", LOG_ERROR
    exc.show
  end
end

def datify time
  # feel the pain!
  Date.strptime(time.strftime(DATEFORMAT), DATEFORMAT)
end

@options = Struct.new(:title, :ttl, :configfile, :verbosity, :fakeness,
  :host, :user, :port, :prefix, :httppre).new

def options_per_default
  @options.title			= nil
  @options.ttl				= 30
  @options.configfile = nil
  begin
    @options.configfile		= ENV['HOME'] + '/.oneshot-cfg.rb'
  rescue
  end
  @options.verbosity = 0
  @options.fakeness  = 0
  @options.host      = nil
  @options.user      = nil
  @options.prefix    = nil
  @options.port      = nil
  @options.httppre   = nil
end

def create_new_config
  file = <<EOT
# put the following in your ~/.oneshot-cfg.rb (change as needed, of course)
# the file is not created automatically, but you can use shell redirection if you want :)
# created by oneshot #{THEVERSION} on #{Time.now.strftime(DATEFORMAT)}
#
@options.title = 'untitled' if @options.title.nil?
# @options.ttl = 30
# @options.configfile = ENV['HOME'] + '/.oneshot-cfg.rb'
# @options.verbosity = 0
# @options.fakeness = 0
# use @options.host = nil # to trigger local copying of the file, ignoring user&port
@options.host = "myhost.example"  if @options.host.nil?
# @options.user = nil
@options.prefix = "var/www/oneshot/"  if @options.prefix.nil?
# @options.port = nil if @options.port.nil?
@options.httppre = 'http://myhost.example/oneshot/' if @options.httppre.nil?
EOT
end

class Transfer
  attr_accessor :path_local, :path_remote, :description, :url_http

  def initialize path_local = nil, path_remote = nil, description = nil, url_http = nil
    @path_local   = path_local
    @path_remote  = path_remote
    @description  = description
    @url_http     = url_http
  end

  # TODO : this is redefined...
  def path_local escaped = true
    return @path_local unless escaped
    return @path_local.shellescape
  end
end

class Switch
  attr_accessor :char, :comm, :args, :code

  def initialize char, comm, args, code
    @char = char
    @comm = comm
    @args = args
    @code = code
  end
end

def options_from_file filename
  begin
    log "gonna load config file", LOG_DEBUG
    log "config file not found", LOG_ERROR unless File.exist?(filename)
    if File.exist?(filename)
      load filename
      log "loaded config file", LOG_INFO
    end
  rescue => exc # FIXME does not seem to work when removing the file.exists?
    log "error loading config file", LOG_ERROR
    STDERR.puts exc.backtrace
  end
end

def options_from_cmd
  log ARGV.join(' '), LOG_DEBUG

  current_transfer = Transfer.new()
  @transfers = []
  @switches = nil # for scoping
  @helpswitch = Switch.new('h', 'print help message',	false, proc { puts "this is oneshot #{THEVERSION}"; switches.each { |e| puts '-' + e.char + "\t" + e.comm }; Process.exit })
  @switches = [
    Switch.new('f', 'specify remote filename for next file',	true, proc { |val| current_transfer.path_remote = val }),
    Switch.new('d', 'specify remote description for next file', true, proc { |val| current_transfer.description = val }),
    Switch.new('t', 'specify title used in URL',				true, proc { |val| @options.title = val }),

    Switch.new('x', 'specify ttl, days until remote file may be removed', true, proc { |val| @options.ttl = val }),

    Switch.new('c', 'specify local configfile', true, proc { |val| @options.configfile = val }),

    Switch.new('o', 'specify sftp host, "nil" triggers local copying, ignoring user&port',        	true, proc { |val| @options.host = val }),
    Switch.new('u', 'specify sftp user',			true, proc { |val| @options.user = val }),
    Switch.new('l', 'specify remote base location',	true, proc { |val| @options.prefix = val }),
    Switch.new('p', 'specify sftp port',			true, proc { |val| @options.port = val }),

    Switch.new('e', 'specify http prefix',	true, proc { |val| @options.httppre = val }),

    Switch.new('v', 'increase verbosity',	false, proc { @options.verbosity += 1 }),
    Switch.new('w', 'increase fakeness',	false, proc { @options.fakeness += 1 }),

    Switch.new('b', 'pastebin mode opens a textedit window', false,
      proc { f = '/tmp/oneshot.pastebin.txt'
             msg = `kdialog --textinputbox "Please paste the text to upload here:" "" 300 300 > #{f}`;
             @onfile.call(f)
      }
    ),
    Switch.new('g', 'gallery with jpg thumbs',	false, proc { $thumbs.enable }),

    Switch.new('i', 'create new config file, nondestructive',   false, proc { log(create_new_config, LOG_OUTPUT) ; Process.exit }),
    Switch.new('s', 'run serverside test, searching outdated files',    true, proc { |val| serverside_check val ; Process.exit }),
    @helpswitch
  ]

  @onfile = proc { |filename| current_transfer.path_local = filename; @transfers << current_transfer; current_transfer = Transfer.new()};
  onstuff = proc {|someswitch| log "there is no switch '#{someswitch}'\n\n", LOG_ERROR; @helpswitch.code.call; Process.exit };

  notargs = []

  ARGV.each_index { |i|
    next if notargs.include?(i)

    arg = ''.replace(ARGV[i]) #FIXME: unfreeze

    if arg[0..0] == '-'
      arg[1..-1].scan(/./) do |chr|
        notargs << i+1 if call_switch(chr, ARGV[i+1])
      end
    else
      @onfile.call(ARGV[i])
    end
  }
end

def call_switch chr, argument
  myswitch = @switches.find {|s| s.char == chr}
  onstuff.call(chr) if myswitch.nil?
  if myswitch.args
    myswitch.code.call(argument)
    return true
  else
    myswitch.code.call
    return false
  end
end

def sanatize_options
  if @options.title.nil? or @options.title == "untitled"
    unless @transfers.nil? or @transfers.length == 0
      @options.title = File.basename(@transfers.first.path_local(false))
    end
  end
  @options.title = @options.title.asciify
  @options.ttl = @options.ttl.to_s
  #@options.configfile = ENV['HOME'] + '/.nscripts/oneshot-cfg.rb'
  #@options.verbosity = 0
  #@options.fakeness = 0
  #@options.host = nil
  #@options.user = nil # TODO set to something sane if it was empty.
  @options.prefix = '' if @options.prefix.nil?
  @options.port = @options.port.to_s unless @options.port.nil?
  #@options.httppre = nil

  @transfers.each { |t|
    # is escaped now automagically
    # t.path_local  = t.path_local.shellescape
    t.path_remote = t.path_local(false) if t.path_remote.nil?
    t.path_remote = File.basename(t.path_remote)
    t.path_remote = t.path_remote.asciify.shellescape
  }
end

def print_options
  log "options:\n", LOG_INFO
  @options.each_pair { |name, val|
    name = name.to_s
    val = val.to_s
    log pad(name, ' ', nil, 10) + " = " + val.to_s, LOG_INFO
  }

  @transfers.each { |t|
    tmp  = 'upload: '		+ t.path_local.quote
    tmp += ' goes to '	+ t.path_remote.quote unless t.path_remote.nil?
    tmp += ' tagged '		+ t.description.quote unless t.description.nil?
    log tmp, LOG_INFO
  }
end

def transferstring transfer, expiry
  ending = File.extname(transfer.path_remote)
  ending.slice!(0)
  ending = "empty" if ending.nil? or ending.length < 1 # TODO check against whitelist to disable inclusion of abitrary files...
  ending.downcase!

  thumburl = $thumbs.index_thumb_url transfer, "http://nailor.devzero.de/mime/#{ending}.png"
  thumbwidth = $thumbs.index_thumb_width transfer, 128

  <<EOT
  <table border="0">
    <tr>
      <td rowspan="2">
        <a class="nodeco" href="#{transfer.path_remote}">
          <img class="nodeco" src="#{thumburl}" alt="mime #{ending}" width="#{thumbwidth.to_s}" height="128"/>
        </a>
      </td>
    </tr>
    <tr>
      <td>
        <h2><a href="#{transfer.path_remote}">#{transfer.path_remote}</a></h2>
        <a class="hanging" href="javascript:show('xx#{transfer.path_remote}')">&rarr; details</a>
      </td>
    </tr>
  </table>

    <ul id="xx#{transfer.path_remote}" style="display:none;">
    <li #{'style="display:none;"' if transfer.description.nil?}>
                  #{transfer.description.nil? ? "" : transfer.description}                </li>
    <li>uploaded: #{Time.now.strftime(DATEFORMAT)}                                        </li>
    <li>expires:  #{expiry.strftime(DATEFORMAT)}                                          </li>
    <li>size      #{(File.size(transfer.path_local(false)).to_f / (1024*1024)).to_s(3)} MB</li>
    <li>sha1:     #{hashsum(transfer.path_local(false))}                                  </li>
    </ul>
EOT
end

def generate_dir_list expiry
  table = ''

  @transfers.each { |t|
    table += transferstring(t, expiry)
  }

  result =   <<EOT
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
   "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
    <title>oneshot - upload - #{@options.title}</title>

<style type="text/css">
body { background-color: #4F7E9E; }
* { font-family: sans-serif; }

pre { font-family: monospace; }
ul { margin-left: 1.0em; margin-bottom: 0.1em; }

h1 { color: #000000; margin-left: 0.1em; margin-top: 0.2em; }
h2 { color: #000000; }

hr { color: #E6DACF; background-color: #E6DACF; height: 0.1em; border: 0; }

a { color: black; text-decoration: none; font-weight: bold; }
a:hover { color: #E6DACF; }

.pre { font-family: monospace; }
.nodeco { text-decoration: none; border: 0 }
.hanging { margin-left: 0.5em; margin-top: 0px; }
.invisible { color: #4F7E9E; }
</style>

<script type="text/javascript">
 //<![CDATA[

  function show(what) {
    if (document.getElementById(what).style.display=='none')
      document.getElementById(what).style.display='block';
    else
      document.getElementById(what).style.display='none';
  }

 //]]>
</script>
</head>

<body>
    <table border="0">
      <tr>
        <td>
          <a class="nodeco" href="http://validator.w3.org/check?uri=referer">
            <img class="nodeco" src="http://www.w3.org/Icons/valid-xhtml11-blue" alt="Valid XHTML 1.1" height="31" width="88" />
          </a>
        </td>
        <td><h1>oneshot - upload - #{@options.title}</h1></td>
      </tr>
    </table>

    <div>
      #{table}
    </div>

  <div class="invisible">
    <a class="invisible" href="http://gnome-look.org/content/show.php?content=81153">icons from buuf1.04.3</a>
    <a class="invisible" href="http://creativecommons.org/licenses/by-nc-sa/3.0/deed.de">icons licensed under Creative Commons BY-NC-SA</a>
  </div>
</body>
</html>
EOT

  log result, LOG_DEBUG
  return result
end

class Uploader
  def initialize options, transfers, indexfile, ttlfile
    @options, @transfers, @indexfile, @ttlfile = options, transfers, indexfile, ttlfile
  end
end

class SFTPUploader < Uploader
  # create the list of sftp-commands to be issued
  # the path to the index and expiry-file are passed
  def create_sftp_commands indexfile, expiryfile
    date = Time.now.strftime("%Y-%m-%d")
    hsh  = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..15)

    cmds  = ""
    cmds += "EOF\n"
    cmds += "-mkdir #{date}\n"
    cmds += "cd #{date}\n"
    cmds += "-mkdir #{@options.title}\n"
    cmds += "cd #{@options.title}\n"
    cmds += "mkdir #{hsh}\n"
    cmds += "cd #{hsh}\n"

    # upload the expiry-file first
    cmds += "put #{expiryfile} .oneshot-expiry\n"
    cmds += "put #{indexfile} index.htm\n"

    prefix = @options.httppre + date + '/' + @options.title + '/' + hsh + '/'

    @transfers.each { |t|
      cmds += "put #{t.path_local} #{t.path_remote}\n"
      cmds += "chmod 644 #{t.path_remote}\n"
      t.url_http = prefix + t.path_remote
    }

    $thumbs.get_my_transfers.each { |t|
      cmds += "put #{t.path_local} #{t.path_remote}\n"
      cmds += "chmod 644 #{t.path_remote}\n"
    }
    cmds += "EOF\n"

    $idxrem = prefix + 'index.htm'

    return cmds
  end

  def run_sftp commands
    verbosity_switch = ""
    output_redirection = "1> /dev/null 2>/dev/null"
    if @options.verbosity >= LOG_DEBUG
      verbosity_switch = "-v"
      output_redirection = ""
    end
    user_string = ""
    user_string = @options.user + "@" unless @options.user.nil?
    port_string = ""
    port_string = "-oPort=#{@options.port}" unless @options.port.nil?
    real_command = "sftp #{verbosity_switch} #{port_string} -C #{user_string}#{@options.host}#{':' + @options.prefix} #{output_redirection} << #{commands}"
    log real_command, LOG_INFO
    log '### oneshot: calling sftp ###', LOG_DEBUG
    system real_command if @options.fakeness == 0
    log '### oneshot: called  sftp ###', LOG_DEBUG
    state = $?
    log "command returned: " + state.to_s, LOG_INFO
    log "SFTP ERROR!!!", LOG_ERROR unless state == 0
    log '----- ----- ----- -----', LOG_INFO

    @transfers.each { |t|
      log t.url_http, LOG_INFO
    } if state == 0

    return state
  end

  def run!
    sftp_commands = create_sftp_commands @indexfile, @ttlfile
    state = -1
    state = run_sftp sftp_commands
    log $idxrem, LOG_OUTPUT if state == 0
  end
end

class LocalUploader < Uploader
  require 'fileutils'

  def run!
    date = Time.now.strftime("%Y-%m-%d")
    hsh  = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..15)

    dir = "#{@options.prefix}/#{date}/#{@options.title}/#{hsh}/"
    dirhttp = "#{@options.httppre}/#{date}/#{@options.title}/#{hsh}/"
    FileUtils.makedirs(dir)

    FileUtils.cp(@ttlfile, "#{dir}/.oneshot-expiry")
    FileUtils.cp(@indexfile, "#{dir}/index.htm")

    @transfers.each { |t|
      FileUtils.cp(t.path_local(false), dir + t.path_remote)
      File.chmod(0644, dir + t.path_remote)
      t.url_http = dirhttp + t.path_remote
    }


    $thumbs.get_my_transfers.each { |t|
      FileUtils.cp(t.path_local(false), dir + t.path_remote)
      File.chmod(0644, dir + t.path_remote)
    }

    idxrem = dirhttp + 'index.htm'
    log idxrem, LOG_OUTPUT
  end
end

begin
  $thumbs = Thumbnails.new
  options_per_default
  options_from_cmd
  options_from_file @options.configfile

  sanatize_options
  print_options

  if @transfers.empty?
    log "found no files to transfer\n\n", LOG_ERROR
    @helpswitch.code.call
  end

  @transfers.each { |transfer|
    $thumbs.add_file(transfer)
  }

  tempfile_list = tempfilename
  tempfile_expire = tempfilename + '.ttl'

  expiry = Time.now + @options.ttl.to_f * 60 * 60 * 24
  log "expires on " + expiry.strftime(DATEFORMAT), LOG_INFO

  htmllist = generate_dir_list expiry

  File.open(tempfile_list, 'w+') { |f| f.puts htmllist }
  File.open(tempfile_expire, 'w+') { |f| f.puts expiry.strftime(DATEFORMAT) }

  if @options.host.nil?
    x = LocalUploader.new(@options, @transfers, tempfile_list, tempfile_expire)
    x.run!
  else
    x = SFTPUploader.new(@options, @transfers, tempfile_list, tempfile_expire)
    x.run!
  end
rescue => exc
  exc.show
  exit 1
end
