package Cobalt::Common;
our $VERSION = '0.02';

use strict;
use warnings;

use base 'Exporter';
## Import a bunch of stuff very commonly useful to Cobalt plugins.

use Cobalt::Utils qw/ :ALL /;

use IRC::Utils qw/ 
  decode_irc
  lc_irc eq_irc uc_irc 
  normalize_mask matches_mask
  strip_color strip_formatting
  parse_user
  is_valid_nick_name
  is_valid_chan_name
/;

use Object::Pluggable::Constants qw/ PLUGIN_EAT_NONE PLUGIN_EAT_ALL /;

our %EXPORT_TAGS = (
  string => [ qw/
  
    rplprintf color

    glob_to_re glob_to_re_str glob_grep
    
    lc_irc eq_irc uc_irc
    decode_irc
    
    strip_color
    strip_formatting
    
  / ],
  
  passwd => [ qw/

    mkpasswd passwdcmp

  / ],
  
  time   => [ qw/
    
    timestr_to_secs secs_to_timestr

  / ],

  valid  => [ qw/
    
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
);

our @EXPORT;

{
  my %seen;
  push @EXPORT,
    grep {!$seen{$_}++} @{$EXPORT_TAGS{$_}} foreach keys %EXPORT_TAGS; 
}

sub import {
  strict->import;
  warnings->import;
  feature->import( ':5.12' );
  __PACKAGE__->export_to_level(1, @_);  
}

1;
__END__

=pod

=head1 NAME

Cobalt::Common - import commonly-used tools and constants

=head1 SYNOPSIS

  package Cobalt::Plugin::User::MyPlugin;
  our $VERSION = '0.10';

  ## Import useful IRC::Utils / Cobalt::Utils / constants
  ## also get strict, warnings, 5.12 features
  use Cobalt::Common;

=head1 DESCRIPTION

This is a small exporter module providing easy inclusion of commonly 
used tools and constants.

By default, B<strict>, B<warnings>, and the B<5.12> feature set are 
also enabled (but it's still good practice to make use of them. Life 
sucks when you start forgetting later!)

=head2 Exported

=head3 Constants

=over

=item *

PLUGIN_EAT_NONE (L<Object::Pluggable::Constants>)

=item *

PLUGIN_EAT_ALL (L<Object::Pluggable::Constants>)

=back

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

=head3 Cobalt::Utils

See L<Cobalt::Utils> for details.

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

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
