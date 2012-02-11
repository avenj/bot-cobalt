package Cobalt::Common;
our $VERSION = '0.04';

## Import a bunch of stuff very commonly useful to Cobalt plugins
##
## Does some Evil; the importing package will also have strict, warnings, 
## and the '5.12' featureset ('say', 'given/when', 'unicode_strings' ..)

use 5.12.1;  ## because you're gonna need it
use strict;
use warnings;

use Carp;

use base 'Exporter';

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

use Object::Pluggable::Constants qw/ 
  PLUGIN_EAT_NONE 
  PLUGIN_EAT_ALL 
/;

## FIXME: These sets should be documented .. eventually ..

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
    croak
    confess
  / ],
  
  passwd => [ qw/

    mkpasswd passwdcmp

  / ],
  
  time   => [ qw/
    
    timestr_to_secs secs_to_timestr

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
);

our @EXPORT;

## see perldoc Exporter:
{
  my %seen;
  push @EXPORT,
    grep {!$seen{$_}++} @{$EXPORT_TAGS{$_}} for keys %EXPORT_TAGS; 
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

  ## Import useful stuff from:
  ##  IRC::Utils
  ##  Cobalt::Utils
  ##  Object::Pluggable::Constants
  ## also get strict, warnings, 5.12 features
  use Cobalt::Common;

=head1 DESCRIPTION

This is a small exporter module providing easy inclusion of commonly 
used tools and constants.

By default, B<strict>, B<warnings>, and the B<5.12> feature set are 
also enabled (but it's still good practice to explicitly make use of 
them -- life sucks when you start forgetting later . . . )


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

=head3 Carp

=head4 Warnings

  carp
  
=head4 Errors

  croak
  confess

=head1 BUGS

Your namespace will be full of Stuff.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
