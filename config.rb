# TODO make clear that this is only for file_upload.cgi

fn = "config.local.rb"

if FileTest.exists?(fn)
  require fn
else
  throw "could not load config, fill it with something like the comment further up in this file"
end
