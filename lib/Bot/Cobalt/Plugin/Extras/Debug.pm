package Bot::Cobalt::Plugin::Extras::Debug;
our $VERSION = '0.012';

## Simple 'dump to stdout' debug functions
##
## IMPORTANT: NO ACCESS CONTROLS!
## Intended for debugging, you don't want to load on a live bot.
##
## Dumps to STDOUT, there is no IRC output.
##
## Commands:
##  !dumpcfg
##  !dumpstate
##  !dumptimers
##  !dumpservers
##  !dumplangset
use 5.10.1;
use strict;
use warnings;

use Data::Dumper;

use Object::Pluggable::Constants qw/ PLUGIN_EAT_NONE /;

sub new { bless [], shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  my @events = map { 'public_cmd_'.$_ } 
    qw/
      dumpcfg 
      dumpstate 
      dumptimers 
      dumpservers
      dumplangset
    / ;

  register( $self, 'SERVER',
    [ @events ] 
  );

  $core->log->info("Loaded DEBUG");

  $core->log->warn(
    "THIS PLUGIN IS FOR DEVELOPMENT PURPOSES",
    "You do not want to run this plugin on a live bot;",
    "it has no access controls!"
  );
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unloaded DEBUG");
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumpcfg {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumpcfg called (debugger)");
  $core->log->warn(Dumper $core->cfg);
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumpstate {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumpstate called (debugger)");
  $core->log->warn(Dumper $core->State);
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumptimers {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumptimers called (debugger)");
  $core->log->warn(Dumper $core->TimerPool);
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumpservers {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumpservers called (debugger)");
  $core->log->warn(Dumper $core->Servers);
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumplangset {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumplangset called (debugger)");
  $core->log->warn(Dumper $core->lang);
  return PLUGIN_EAT_NONE
}

1;
__END__
=pod

=head1 NAME

Bot::Cobalt::Plugin::Extras::Debug - Dump internal state information

=head1 SYNOPSIS

  !plugin load Bot::Cobalt::Plugin::Extras::Debug
  !dumpcfg
  !dumplangset
  !dumpservers  
  !dumpstate
  !dumptimers

=head1 IMPORTANT

B<This plugin has no access controls!>

It is intended to be used strictly for debugging during development.

If it is loaded, anyone can flood STDOUT using the dump commands.

=head1 DESCRIPTION

This is a simple development tool allowing developers to dump the 
current contents of various core attributes to STDOUT for inspection.

References are displayed using L<Data::Dumper>.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
