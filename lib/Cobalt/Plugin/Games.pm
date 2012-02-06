package Cobalt::Plugin::Games;
our $VERSION = '0.11';

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = @_;
  $self->{core} = $core;

  $self->_load_games;

  $core->plugin_register($self, 'SERVER',
    [ 'public_msg' ],
  );

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}

sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg = ${ $_[1] };

  return PLUGIN_EAT_NONE unless $msg->{cmdprefix};
  
  my $prefixedcmd = $msg->{message_array}->[0];
  my $cmd = substr($prefixedcmd, 1);
  $cmd = lc($cmd||'');
  
  return PLUGIN_EAT_NONE
    unless $cmd and defined $self->{Dispatch}->{$cmd};

  my $game = $self->{Dispatch}->{$cmd};
  my $obj  = $self->{Objects}->{$game};
  
  my @message = @{ $msg->{message_array} };
  my $str  = join ' ', @message[1 .. $#message];
  
  my $resp = $obj->execute($msg, $str);

  $core->send_event( 'send_message',
    $context,
    $msg->{target},
    $resp
  );

  return PLUGIN_EAT_NONE
}

sub _load_games {
  my ($self) = @_;
  my $core = $self->{core};
  
  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $games = $pcfg->{Games} // {};

  $core->log->debug(scalar keys %$games." games found");

  for my $game (keys %$games) {
    my $module = $games->{$game}->{Module} // next;
    next unless ref $games->{$game}->{Cmds} eq 'ARRAY';

    ## attempt to load module
    eval "require $module";
    if ($@) {
      $core->log->warn("Failed to load $module - $@");
      next
    } else {
      $core->log->debug("Found: $module");
    }

    my $obj = $module->new(core => $core);
    $self->{Objects}->{$game} = $obj;
    ## build a hash of commands we should handle
    for my $cmd (@{ $games->{$game}->{Cmds} }) {
      $self->{Dispatch}->{$cmd} = $game;
    }
    
    $core->log->debug("Game loaded: $game");
  }

}


1;
