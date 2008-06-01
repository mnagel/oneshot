#!/usr/bin/env ruby 

# TODO DONE generate dir-listing
# TODO DONE generate ttl-file
# TODO handle file path. locally allow, remote -> flatten (if local is path and remote nil, or remote path)
# TODO cleanup code
# TODO cleanup switches
# TODO document code
# TODO revise verbosity
# TODO revise fakeness
#
# round 2 :
# TODO handle wrong command line switches
# TODO WONTFIX support scp --> does not allow mkdir...
# TODO remove temporary files
# TODO include information about oneshot into html listing
# TODO warn multiple files same name
# TODO handle spaces in filenames, remove(?) sftp does not like them
# TODO above applies for descpription used in URL, too. its ok on html-list, though
# TODO make nicer output (listing html)
# TODO DONE make nicer output (console)
# TODO DONE allow keyboard auth
# TODO revise sftp return code handling
# TODO revise sftp output redirection
# TODO allow generation of config-file
# 
# delayed: 
# TODO generate cleanup tool
#


require 'digest/sha1'
require 'time'

THEVERSION = "0.0.1"

# file lib/shellwords.rb, line 69
def shellescape(str)
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

@options = Struct.new( 
  :subject,
  :ttl,
  :configfile,
  :verbosity,
  :fakeness,
  :host,
  :user,
  :prefix,
  :port,
  :httppre
).new

def options_per_default
  @options.subject = nil
  @options.ttl = 30
  @options.configfile = ENV['HOME'] + '/.nscripts/oneshot-cfg.rb'
  @options.verbosity = 0
  @options.fakeness = 0
  @options.host = nil
  @options.user = nil
  @options.prefix = nil
  @options.port = nil
  @options.httppre = nil
end

def log string, level
  puts string unless @options.verbosity < level
end

class TRANSFER < Struct.new(:local, :remote, :desc, :urlhttp); end
class SWITCH < Struct.new(:char, :comm, :args, :code); end

def options_from_file file
  begin
	log "gonna load config file", 2
	log "config file not found", 0 unless File.exist?(file)
	if File.exist?(file)
	  load file
	  log "loaded config file", 2
    end
  rescue => exc # FIXME does not seem to work when removing the file.exists?
	log "error loading config file", 0
  end
end

def options_from_cmd
  log ARGV.join(' '), 2

  currentTransfer = TRANSFER.new()
  @transfers = []
  switches = nil  
  switches = [

	SWITCH.new('f', 'specify remote filename for next file',	true, proc { |val| currentTransfer.remote = val }),
	SWITCH.new('d', 'specify remote description for next file', true, proc { |val| currentTransfer.desc = val }),
	SWITCH.new('s', 'specify subject used in URL',				true, proc { |val| @options.subject = val }),

	SWITCH.new('e', 'specify ttl, remote file can be deleted then', true, proc { |val| @options.ttl = val }),

	SWITCH.new('c', 'specify local configfile', true, proc { |val| @options.configfile = val }),

	SWITCH.new('o', 'specify sftp host',			true, proc { |val| @options.host = val }),
	SWITCH.new('u', 'specify sftp user',			true, proc { |val| @options.user = val }),
	SWITCH.new('l', 'specify remote base location', true, proc { |val| @options.prefix = val }),
	SWITCH.new('p', 'specify sftp port',			true, proc { |val| @options.port = val }),
	
	SWITCH.new('x', 'specify http prefix',	true, proc { |val| @options.httppre = val }),

	SWITCH.new('v', 'increase verbosity',	false, proc { @options.verbosity += 1 }),
	SWITCH.new('w', 'increase fakeness',	false, proc { @options.fakeness += 1 }),

	SWITCH.new('h', 'print help message',	false, proc { switches.each { |e| puts '-' + e.char + "\t" + e.comm }; Process.exit })
  ]

  onfile = proc { |filename| currentTransfer.local = filename; @transfers << currentTransfer; currentTransfer = TRANSFER.new()}

  eatarg = -1 

  ARGV.each_index do |i|
	next if i == eatarg

	arg = ''.replace(ARGV[i]) # unfreeze!
	# puts "parsing #{arg}"

	if arg.slice(0..0) == '-'
	  arg.slice(1..-1).scan(/./) do |chr|
		myswitch = switches.select{|s| s.char == chr}.first
		myswitch = switches.last if myswitch.nil?
		if myswitch.args == true
		  myswitch.code.call(ARGV[i+1])
		  eatarg = i+1
		else
		  myswitch.code.call
		end
	  end
	else
	  onfile.call(ARGV[i])	  
	end
  end
end

def pad pre, char, len
  return pre + char * [len - pre.length, 0].max
end

def rpad pre, char, len
  return char * [len - pre.length, 0].max + pre
end

def q s
  return '"' + s + '"'
end

def sanatize_options
  @options.subject = shellescape @options.subject
  @options.ttl = @options.ttl.to_s
  #@options.configfile = ENV['HOME'] + '/.nscripts/oneshot-cfg.rb'
  #@options.verbosity = 0
  #@options.fakeness = 0
  #@options.host = nil
  #@options.user = nil
  #@options.prefix = nil
  @options.port = @options.port.to_s unless @options.port.nil?
  #@options.httppre = nil
	 
  @transfers.each { |t|
	t.local = shellescape t.local
	t.remote = shellescape t.remote unless t.remote.nil?
  }
end

def print_options
  log "options:\n", 1
  @options.each_pair { |name, val|
	name = name.to_s
	val = val.to_s
	log pad(name, ' ', 10) + " = " + val.to_s, 1
  }
  
  @transfers.each { |t| 
	a = 'upload: ' + q(t.local)
	a += ' goes to ' + q(t.remote) unless t.remote.nil? 
	a += ' tagged ' + q(t.desc) unless t.desc.nil? 
	log a, 1
  }
end

def create_sftp_commands
  date = Time.now.strftime("%Y-%m-%d") # -%H:%M-%S")
  hsh = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..15)

  sftp_commands  = ""
  sftp_commands += "EOF\n"
  sftp_commands += "-mkdir #{date}\n"
  sftp_commands += "cd #{date}\n"
  sftp_commands += "-mkdir #{@options.subject}\n"
  sftp_commands += "cd #{@options.subject}\n"
  sftp_commands += "mkdir #{hsh}\n"
  sftp_commands += "cd #{hsh}\n"

  @transfers.each { |t|
	sftp_commands += "put #{t.local} #{t.remote}\n"
	t.urlhttp = @options.httppre + date + '/' + @options.subject + '/' + hsh + '/' + (t.remote.nil? ? t.local : t.remote)
  }
  
  sftp_commands += "put #{@tfn} index.htm\n"
  sftp_commands += "put #{@ttlname} .oneshot-expiry\n"
  sftp_commands += "EOF\n"
  
  @idxrem = @options.httppre + date + '/' + @options.subject + '/' + hsh + '/index.htm'
  
  return sftp_commands
end

def tempfilename
  hsh = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..7)
  return "/tmp/oneshot-#{hsh}.htm"
end

def generate_dir_list expiry
  result = <<EOT
<?xml version="1.0" ?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <title>oneshot - upload - #{@options.subject}</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <style type="text/css">
      * { 
       font-family: monospace; 
      }
	  ul {
		  padding-bottom: 1.5em;
	  }
    </style>
  </head>
  <body>

    <h1>oneshot - upload - #{@options.subject}</h1>
    <div>

	#{  res = ''
  @transfers.each { |t|
  temp = ''
  name = t.remote.nil? ? t.local : t.remote
  temp += '<h2><a href="' + name + '">' + name + '</a></h2>'
  temp +='<ul>'
  desc = t.desc #t.desc.nil? ? "no description" : t.desc
  temp += '<li>' + desc + '</li>' unless t.desc.nil?
  date = Time.now.strftime("%Y-%m-%d %H:%M:%S")
  date2 = expiry.strftime("%Y-%m-%d %H:%M:%S")
  temp += '<li>uploaded: ' + date + '</li>'
  temp += '<li>min. online until: ' + date2 + '</li>'
  hash = "sha1: " + Digest::SHA1.hexdigest(File.read(t.local))
  temp += '<li>' + hash + '</li>'
  temp += "</ul>\n"
  res += temp
  }
  res
  }  
  </div>

  </body>
  </html>
EOT
  

  
  log result, 2
  return result
end

begin
  options_per_default
  options_from_cmd
  options_from_file @options.configfile
  
  sanatize_options
  print_options
  
  @tfn = tempfilename
  @ttlname = tempfilename + '.ttl'
  
  expiry = (Time.now + @options.ttl.to_f * 60 * 60 * 24)   #strftime("%Y-%m-%d") # -%H:%M-%S")
  # puts expiry
  #s = Time.parse(expiry)
  log expiry.strftime("%Y-%m-%d-%H:%M:%S"), 1
  
  sftp_commands = create_sftp_commands
  mystring = generate_dir_list expiry
  

  
  filename = @tfn
  File.open filename, 'w+' do |f|
	f.puts mystring
  end 
  
  filename = @ttlname
  File.open filename, 'w+' do |f|
	f.puts expiry
  end 
  
  real_command = "sftp -C #{@options.host}#{':' + @options.prefix} 1> /dev/null 2>/dev/null << #{sftp_commands}"
  log real_command, 1
  log '### oneshot: calling sftp ###', 2
  system real_command if @options.fakeness == 0
  log '### oneshot: called  sftp ###', 2
  state = $?
  log "command returned: " + state.to_s, 1
  log "SFTP ERROR!!!", 0 unless state == 0 
  log '----- ----- ----- -----', 1
  
  @transfers.each { |t|
	log t.urlhttp, 1
  } if state == 0
  log @idxrem, 0 if state == 0

rescue => exc
  STDERR.puts "there was an error"
  STDERR.puts exc.backtrace * "\n"
  STDERR.puts "E: #{exc.message}"
  #STDERR.puts ARGV.to_s
  exit 1
end
