#COMMAND    = "oneshot"
#CONFIGFILE = "/home/www-data/.oneshot-cfg-local.rb"

fn = "config.local.rb"
if FileTest.exists?(fn)
  require fn
else
  throw "could not load config, fill it with something like the comment further up in this file"
end
