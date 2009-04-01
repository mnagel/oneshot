#!/usr/bin/ruby

# TODO run in sandbox (safely)
# TODO problems with spaces...
# TODO include logging -- send mail!
# TODO allow multiple files
# TODO problems with no file at all...

# send a mail to the authors
def report_feedback string="", subject=""
  string = "" if string.nil?
  subject = "" if subject.nil?

  require 'net/http'
  require 'cgi'

  text = CGI::escape <<EOT
TEXT TO MAKE MAIL END HEADERS

#{string}

----- ADDITIONAL INFORMATION -----

- no additional information -

EOT

  subject = CGI::escape("[OS] #{subject}")

  Net::HTTP.start("nailor.devzero.de") { |http|
    http.get("/quickmail/mail.cgi?str=#{text}&sub=#{subject}")
  }
end

report_feedback "gonna upload something...", "start"

require 'config.rb'

require 'cgi'
require 'stringio'
require 'digest/sha1'

$buffer = ""

def log *str
  begin
    if str.nil?
      str = ""
    else
      str = str.first
    end
    str = "" if str.nil?
    $buffer += str + "<br />"
  rescue => exc
    $buffer += "<b>something fishy...</b>"
    exc.show
    raise
  end
end

def fire
  report_feedback($buffer, "!!! FAIL !!!")
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

def tempfilename
  hsh = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..15)
  return "/tmp/oneshotupload-#{hsh}.bin"
end

# BEGIN MAIN SCRIPT HERE...
begin
  cgi = CGI.new("html4")
  orig = cgi.params['myfile'].first.original_filename
  tmpfile = cgi.params['myfile'].first.path
  thing = cgi.params['myfile'].first
  fn = tempfilename

  File.open(fn, 'w') { |file| file << thing.read}

  #TODO remove file
  #File.safe_unlink(fn)
  filename = fn
  name_it = orig.asciify.shellescape
  cmd = "#{COMMAND} -c #{CONFIGFILE} -f #{name_it} #{filename}"
  #      log "running #{cmd}"
  url = %x[#{cmd}]

  print cgi.header({'status'=>'REDIRECT', 'Location'=>url})
  report_feedback "they say it landed at: \n#{url}", "finish"

rescue => eee
  fire
end