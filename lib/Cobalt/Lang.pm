package Cobalt::Lang;
our $VERSION = "0.14";

## Emitted events:
##  langset_loaded ($lang, $lang-specified, $path)
##
## Loads from __DATA__ first (added at build-time by Lang.pm.PL)
## This provides an up-to-date default English set in case the 
## on-disk langset is old / incomplete / broken / missing.

use 5.12.1;
use strict;
use warnings;
use Carp;

use Moose;
use namespace::autoclean;

use Cobalt::Serializer;

sub langset_load { load_langset(@_) }
sub load_langset {  ## load_langset(language)
  ## read specified language out of etc/langs/
  ## return hash suitable for core->lang
  my ($self) = shift;
  my $lang = shift || croak 'no language specified?';
  ## you can specify a prefix
  ## f.ex: load_langset('english', '/some/dir/langs/plugin-')
  ## results in: $path = "/some/dir/langs/plugin-". lc($lang) .".yml"
  my $prefix = shift || $self->cfg->{path} . "/langs/";

  ## etc/langs/language.yml (lowercase expected)
  my $path = $prefix . lc($lang) . ".yml";

  unless (-f $path) {
    $self->send_event( 'langset_error', "not found: ($lang) $path" )
      if $self->can('send_event');
    $self->log->debug("langset not found: $lang ($path)")
      if $self->can('log');
    return { }
  }

  $self->log->info("Loading language set: $lang")
    if $self->can('log');

  my %opts;
  $opts{Logger} = $self->log if $self->can('log');
  my $serializer = Cobalt::Serializer->new(%opts);
  my $langset = $serializer->readfile($path);

  ## Load __DATA__'s english langset first:
  my $default_langset_yaml = __DATA__;
  my $default_langset = $serializer->thaw($default_langset_yaml);
  
  ## Push anything missing in $langset
  ## (but only if there was no prefix specified)
  ## If there was, this is probably a plugin langset
  unless ($prefix) {
    for my $rpl (keys %{ $default_langset->{RPL} }) {
      unless (exists $langset->{RPL}->{$rpl}) {
        my $default_repl = $default_langset->{RPL}->{$rpl};
        $langset->{RPL}->{$rpl} = $default_repl;
        $self->log->debug("pushed missing RPL from default set: $rpl")
          if $self->can('log');
      }
    }
  }

  ## FIXME langset validation ?

  unless (scalar keys %{ $langset->{RPL} }) {
    $self->send_event( 'langset_error', "empty langset? $lang ($path)" )
      if $self->can('send_event');

    $self->log->debug("empty language set? no keys for $lang ($path)")
      if $self->can('log');
    return { }
  }

  $self->send_event( 'langset_loaded', lc($lang), $path )
    if $self->can('send_event');

  return $langset->{RPL}
}

### THIS MODULE WILL HAVE A LANGSET APPENDED AT BUILD-TIME ###

__PACKAGE__->meta->make_immutable;
no Moose; 1;

=pod

=head1 NAME

Cobalt::Lang -- read cobalt2 langsets

=head1 SYNOPSIS

  ## Load an initial langset out of $etcdir/langs/ :
  $core->lang( $core->load_langset('english') );

=head1 DESCRIPTION

Provides language set loading for the Cobalt core.

Langsets should be in a YAML format readable by L<YAML::Syck>.

B<IMPORTANT>: 
Langset names are automatically lowercased. 
Bear this in mind when naming langsets for plugins. 
They should always be lowercase.

Responses are expected to be found in the YAML langset's 'RPL:' key.
(The corresponding hash is what is actually returned when loading a set.)

Typically the keys of the 'RPL' hash contain values which are strings 
potentially containing variables formattable by C<rplprintf> from 
L<Cobalt::Utils>.

Inspect C<etc/langs/english.yml> for an example.

B<
The English langset is built in to this module at install time.

Missing values in the loaded language set will be automatically filled 
by the compiled-in English set, unless this is a prefixed plugin set.
>

Be sure to read the L<Cobalt::Utils> documentation for more on variable 
replacement with C<rplprintf>

=head1 METHODS

=head2 load_langset

Used by the core to load a specified language set.

If passed a single argument, loads the specified .yml file 
out of $etcdir/langs/:

  ## done by cobalt core to (re)load the ->lang hash:
  $core->lang( $core->load_langset('english') );

B<A single-arg call will fail miserably of it's not referenced via $core.>

If passed two arguments, the second argument is considered to be a 
path prefix.

Plugins can use this to read in a langset file, if they like:

  ## using Cobalt::Lang outside of $core
  require Cobalt::Lang;
  my $lang = Cobalt::Lang->new;
  my $etc = $core->cfg->{path};  ## location of our etc/
  ## read in etc/langs/plugin/myplugin-english.yml:
  my $prefix = $etc . "/langs/plugin/myplugin-";
  my $rpl_hash = $lang->load_langset('english', $prefix);

It is generally advisable that plugins don't modify the $core->lang 
hash unless they are also part of the core distribution.

That being said, if you do so, you may want to check for rehashes 
(if the core reloads ->lang, your changes will go missing).


=head1 EMITTED EVENTS

=head2 langset_loaded

Syndicated when a language set is loaded.

${$_[0]} is the (lowercased) langset name.

${$_[1]} is the path to the set that was loaded.

=head2 langset_error

Syndicated when there is some problem loading a langset.

A string describing the general problem is the only argument.

If an appropriate logger is available, the error will also be logged to 
the 'debug' loglevel.


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut

__DATA__
---
## etc/langs/english.yml
## This is a cobalt2 core langset.
##
## It provides IRC message strings for core plugins incl. Cobalt::IRC
##
## See the Cobalt::Lang docs for information on loading langsets.
## See the Cobalt::Utils docs for help with formatting RPL strings.
##
## The actual replies exist in 'RPL:' below.
## Typically they are strings formattable by Cobalt::Utils::rplprintf
## The list of available variables is documented with each RPL.
##
## Variables with trailing characters can be terminated with %
## e.g. "Running %version%."  -> "Running cobalt 2.00."

NAME: english
REV: 6   ## bump +1 on significant revisions please
SPEC: 0  ## someday there'll be a langspec.

RPL:

 ## Core Cobalt set:

  ## RPL_NO_ACCESS: %nick
  RPL_NO_ACCESS: "%nick%, you are not authorized!"

  ## RPL_PLUGIN_LOAD: %plugin, %module
  RPL_PLUGIN_LOAD: "Plugin loaded: %plugin (%module%)"

  ## RPL_PLUGIN_UNLOAD: %plugin
  RPL_PLUGIN_UNLOAD: "Plugin removed: %plugin"

  ## RPL_PLUGIN_ERR: %plugin, %err
  RPL_PLUGIN_ERR: "Failed plugin load: %plugin%: %err"

  ## RPL_PLUGIN_UNLOAD_ERR: %plugin, %err
  RPL_PLUGIN_UNLOAD_ERR: "Failed plugin unload: %plugin%: %err"

  ## RPL_TIMER_ERR
  RPL_TIMER_ERR: "Failed to add timer; unknown timer_set failure"


 ## Cobalt::IRC:

  ## RPL_CHAN_SYNC: %chan
  RPL_CHAN_SYNC: "Sync complete on %chan"


 ## Plugin::Version:

  ## RPL_VERSION: %version, %perl_v, %poe_v, %pocoirc_v
  RPL_VERSION: "Running %version (perl-%perl_v poe-%poe_v pocoirc-%pocoirc_v%) -- http://www.cobaltirc.org"

  ## RPL_INFO: %version, %plugins, %uptime, %sent
  RPL_INFO: "Running %version%. I have %plugins plugins loaded. I've been up for %uptime and responded %sent times."

  ## RPL_OS: %os
  RPL_OS: "I am running %os"

 ## Plugin::Alarmclock:

  ## ALARMCLOCK_SET: %nick, %secs, %timestr, %timerid
  ALARMCLOCK_SET: "Alarm set to trigger in %secs%s (%nick%) [timerID: %timerid%]"

 ## Plugin::Auth:

  ## Broken syntax RPLs, no args:
  AUTH_BADSYN_LOGIN: "Bad syntax. Usage: LOGIN <username> <passwd>"
  AUTH_BADSYN_CHPASS: "Bad syntax. Usage: CHPASS <oldpass> <newpass>"

  ## AUTH_SUCCESS: %context, %src, %nick, %user, %lev
  AUTH_SUCCESS: "Successful auth [%nick%] (%user - %lev%)"

  ## AUTH_FAIL_*: %context, %src, %nick, %user
  AUTH_FAIL_BADHOST: "Login failed; host mismatch for %user [%src%]"
  AUTH_FAIL_BADPASS: "Login failed; passwd mismatch (%user%)"
  AUTH_FAIL_NO_SUCH: "Login failed; no such user (%user%)"
  
  ## AUTH_CHPASS_*: %context, %src, %nick, %user 
  AUTH_CHPASS_BADPASS: "Specified password doesn't match (%user%)"
  AUTH_CHPASS_SUCCESS: "Password changed (%user%)"


  ## AUTH_STATUS, $nick, $username, $lev
  AUTH_STATUS: "%nick% (%username%) is level %lev%"

  ## AUTH_USER_ADDED, $nick, $username, $mask, $lev
  AUTH_USER_ADDED: "Added username %username% (%mask%) at level %lev%"

  ## AUTH_MASK_ADDED, $mask, $username
  AUTH_MASK_ADDED: ~

  ## AUTH_MASK_DELETED, $mask, $username
  AUTH_MASK_DELETED: ~

  ## AUTH_USER_DELETED, $username, $level
  AUTH_USER_DELETED: ~

  ## AUTH_USER_EXISTS, $username
  AUTH_USER_EXISTS: ~


 ## Plugin::Info3:

  ## INFO_DONTKNOW, %nick, %topic
  INFO_DONTKNOW: "%nick%, I don't know anything about %topic"

  ## INFO_WHAT, %nick
  INFO_WHAT: "%nick%, what?"
  
  ## INFO_TELL_WHO, %nick
  INFO_TELL_WHO: "Tell who what, %nick%?"
  
  ## INFO_TELL_WHAT, %nick, %target
  INFO_TELL_WHAT: "Tell %target% about what, %nick%?"

  ## INFO_ADD, %nick, %topic
  INFO_ADD: "%nick%, %topic has been added."

  ## INFO_DEL, %nick, %topic
  INFO_DEL: "%nick%, %topic has been removed."

  ## INFO_ABOUT, %nick, %topic, %author, %date, %length
  INFO_ABOUT: "(%topic%) added by %author% at %date%. Response is %length% characters"

  ## INFO_REPLACE, %nick, %topic
  INFO_REPLACE: "Alright, %nick%, I just replaced %topic"

  # INFO_ERR_NOSUCH, %nick, %topic
  INFO_ERR_NOSUCH: "Could not find topic %topic%, %nick%."

  # INFO_ERR_EXISTS, %nick, %topic
  INFO_ERR_EXISTS: "%nick%, %topic already exists; perhaps you meant replace?"
  
  INFO_BADSYNTAX_ADD: "Usage: <bot> ADD <topic> <response>"
  INFO_BADSYNTAX_DEL: "Usage: <bot> DEL <topic>"
  INFO_BADSYNTAX_REPL: "Usage: <bot> REPLACE <topic> <new response>"

 ## Plugin::RDB:

  ## RDB_ERR_NO_SUCH_RDB, %nick, %rdb
  RDB_ERR_NO_SUCH_RDB: "%nick%, RDB %rdb% doesn't appear to exist."
  
  ## RDB_ERR_NO_SUCH_ITEM, %nick, %rdb, %index
  RDB_ERR_NO_SUCH_ITEM: "%nick%, RDB %rdb doesn't appear to have item %index"
  
  ## RDB_ERR_ITEM_DELETED, %nick, %rdb, %index
  RDB_ERR_ITEM_DELETED: "%nick%, item %index in RDB %rdb is already deleted."

  ## RDB_ERR_NO_STRING, %nick, %rdb
  RDB_ERR_NO_STRING: "What would you like to add to RDB %rdb%, %nick%?"
  
  ## RDB_ERR_RDB_EXISTS, %nick, %rdb
  RDB_ERR_RDB_EXISTS: "RDB %rdb already exists, %nick%!"
  
  ## RDB_ERR_NOTPERMITTED, %nick, %rdb, %op
  RDB_ERR_NOTPERMITTED: "Operation %op appears to be disallowed."

  ## RDB_CREATED, %nick, %rdb
  RDB_CREATED: "Created RDB %rdb per request of %nick"

  ## RDB_DELETED, %nick, %rdb
  RDB_DELETED: "Deleted RDB %rdb%, %nick"

  ## RDB_ITEM_ADDED, %nick, %rdb, %index
  RDB_ITEM_ADDED: "Added item %index to %rdb for %nick"

  ## RDB_ITEM_DELETED, %nick, %rdb, %index
  RDB_ITEM_DELETED: "Deleted item %index from %rdb per request of %nick"

  ## RDB_ITEM_INFO, %nick, %rdb, %index, %date, %time, %addedby
  ##                %votedup, %voteddown
  RDB_ITEM_INFO: "[rdb: %rdb%] %index%: added by %addedby at %time %date"
