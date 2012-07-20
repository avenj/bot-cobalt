package Bot::Cobalt::Common;
our $VERSION = '0.013';

## Import a bunch of stuff very commonly useful to Cobalt plugins
##
## Does some Evil; the importing package will also have 'strictures 1'
## and the '5.10' featureset ('say', 'given/when', ..)
##  -> under 5.15.9, feature->import no longer seems to work as it did
##     no longer documented.

use 5.10.1;
use strictures 1;

use base 'Exporter';

use Carp;

use Bot::Cobalt::Utils qw/ :ALL /;

use IRC::Utils qw/ 
  decode_irc

  lc_irc eq_irc uc_irc 

  normalize_mask matches_mask

  strip_color strip_formatting

  parse_user

  is_valid_nick_name is_valid_chan_name
/;

use Object::Pluggable::Constants qw/ 
  PLUGIN_EAT_NONE 
  PLUGIN_EAT_ALL 
/;

use MooX::Types::MooseLike::Base qw/:all/;

our %EXPORT_TAGS = (

  string => [ qw/
  
    rplprintf color

    glob_to_re glob_to_re_str glob_grep
    
    lc_irc eq_irc uc_irc
    decode_irc
    
    strip_color
    strip_formatting
    
  / ],

  errors => [ qw/

    carp
    confess
    croak

  / ],
  
  passwd => [ qw/

    mkpasswd passwdcmp

  / ],
  
  time   => [ qw/
    
    timestr_to_secs
    secs_to_timestr 
    secs_to_str

  / ],

  validate => [ qw/
    
    is_valid_nick_name
    is_valid_chan_name

  / ],

  host   => [ qw/
    
    parse_user
    normalize_mask matches_mask
  
  / ],

  constant => [ qw/
    
    PLUGIN_EAT_NONE PLUGIN_EAT_ALL
    
  / ],
  
  types => [
    qw/
    
    Any Defined Undef Bool
    Value Ref Str Num Int
    ArrayRef HashRef CodeRef RegexpRef GlobRef
    FileHandle Object
    AHRef

  / ],
);

our @EXPORT;

## see perldoc Exporter:
{
  my %seen;
  push @EXPORT,
    grep {!$seen{$_}++} @{$EXPORT_TAGS{$_}} for keys %EXPORT_TAGS; 
}

sub import {
  strictures->import;
  feature->import( ':5.10' );
  __PACKAGE__->export_to_level(1, @_);  
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Common - Import commonly-used tools and constants

=head1 SYNOPSIS

  package Bot::Cobalt::Plugin::User::MyPlugin;
  our $VERSION = '0.10';

  ## Import useful stuff:
  use Bot::Cobalt::Common;

=head1 DESCRIPTION

This is a small exporter module providing easy inclusion of commonly 
used tools and constants to make life easier on plugin authors.

L<strictures> is also enabled. This will turn on 'strict' and make all 
warnings fatal.

=head2 Exported

=head3 Constants

=over

=item *

PLUGIN_EAT_NONE (L<Object::Pluggable::Constants>)

=item *

PLUGIN_EAT_ALL (L<Object::Pluggable::Constants>)

=back

=head3 Moo types

All of the L<MooX::Types::MooseLike::Base> types are exported.

See L<MooX::Types::MooseLike::Base> for details.

=head3 IRC::Utils

See L<IRC::Utils> for details.

=head4 String-related

  decode_irc
  lc_irc uc_irc eq_irc
  strip_color strip_formatting

=head4 Hostmasks

  parse_user
  normalize_mask 
  matches_mask

=head4 Nicknames and channels

  is_valid_nick_name
  is_valid_chan_name

=head3 Bot::Cobalt::Utils

See L<Bot::Cobalt::Utils> for details.

=head4 String-related

  rplprintf
  color

=head4 Globs and matching

  glob_to_re
  glob_to_re_str 
  glob_grep

=head4 Passwords

  mkpasswd
  passwdcmp

=head4 Time parsing

  timestr_to_secs
  secs_to_timestr
  secs_to_str

=head3 Carp

=head4 Warnings

  carp

=head4 Errors

  confess
  croak


=head2 Exported tags

You can load groups of commands by importing named tags:

  use Bot::Cobalt::Common qw/ :types :string /;

=head3 constant

Exports PLUGIN_EAT_NONE, PLUGIN_EAT_ALL constants from 
L<Object::Pluggable>.

=head3 errors

Exports carp, croak, and confess from L<Carp>.

=head3 host

Exports parse_user, normalize_mask, and matches_mask from L<IRC::Utils>.

=head3 passwd

Exports mkpasswd and passwdcmp from L<App::bmkpasswd>.

=head3 string

Exports from L<Bot::Cobalt::Utils>: color, rplprintf, glob_to_re, 
glob_to_re_str, glob_grep

Exports from L<IRC::Utils>: lc_irc, eq_irc, uc_irc, decode_irc, 
strip_color, strip_formatting

=head3 time

Exports timestr_to_secs, secs_to_timestr, and secs_to_str from 
L<Bot::Cobalt::Utils>.

=head3 types

Exports the L<Moo> types from L<MooX::Types::MooseLike::Base>.

=head3 validate

Exports is_valid_nick_name and is_valid_chan_name from L<IRC::Utils>. 

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
