package Cobalt::Plugin::Games;
our $VERSION = '0.17';

use 5.10.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;

  my $count = $self->_load_games();

  $core->log->info("$VERSION loaded - $count games");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->debug("Cleaning up our games...");
  for my $module (@{ $self->{ModuleNames}//[] }) {
    $core->unloader_cleanup($module);
  }
  $core->log->info("Unloaded");
  return PLUGIN_EAT_NONE
}

sub _handle_auto {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };
 
  my $context = $msg->context;

  my $cmd = $msg->cmd;
  return PLUGIN_EAT_NONE
    unless defined $self->{Dispatch}->{$cmd};

  my $game = $self->{Dispatch}->{$cmd};
  my $obj  = $self->{Objects}->{$game};
  
  my $msgarr = $msg->message_array;
  my $str = join ' ', @$msgarr;
  
  my $resp = '';
  $resp = $obj->execute($msg, $str) if $obj->can('execute');

  $core->send_event( 'send_message',
    $context,
    $msg->target,
    $resp
  ) if $resp;

  return PLUGIN_EAT_NONE
}

sub _load_games {
  my ($self) = @_;
  my $core = $self->{core};
  
  my $pcfg = $core->get_plugin_cfg( $self );
  my $games = $pcfg->{Games} // {};

  $core->log->debug("Loading games");

  my $count;
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

    push(@{ $self->{ModuleNames} }, $module);

    my $obj = $module->new(core => $core);
    $self->{Objects}->{$game} = $obj;
    ## build a hash of commands we should handle
    for my $cmd (@{ $games->{$game}->{Cmds} }) {

      $self->{Dispatch}->{$cmd} = $game;

      ## install a cmd handler and register for it
      my $handler = sub {
            my $this_self = shift;
            $this_self->_handle_auto(@_)
      };
      
      { no strict 'refs';
          *{__PACKAGE__.'::Bot_public_cmd_'.$cmd} = $handler;
      }
      
      $core->plugin_register( $self, 'SERVER',
        [ 'public_cmd_'.$cmd ],
      );
    }

    ++$count;
    $core->log->debug("Game loaded: $game");
  }

  return $count
}


1;
__END__

=pod

=head1 NAME

Cobalt::Plugin::Games - interface some silly games

=head1 SYNOPSIS

  !roll 2d6    -- Dice roller
  !rps <throw> -- Rock, paper, scissors
  !magic8      -- Ask the Magic 8-ball
  !rr          -- Russian Roulette

=head1 DESCRIPTION

B<Games.pm> interfaces a handful of silly games, mapped to commands 
in a configuration file (usually C<etc/plugins/games.conf>).

=head1 WRITING GAMES

On the backend, commands specified in our config are mapped to 
modules that are automatically loaded when this plugin is.

Games modules are given a 'core' argument in new() that tells them 
where to find the core instance:

  sub new { my %args = @_; bless { core => $args{core} }, shift }

When the specified command is handled, the game module's B<execute> 
method is called and passed the original message hash (as specified 
in L<Cobalt::IRC/Bot_public_msg>) and the stripped string without 
the command:

  sub execute {
    my ($self, $msg, $str) = @_;
    ## We saved {core} in new():
    my $core = $self->{core};
    my $src_nick = $msg->src_nick;
    
    ...

    ## We can return a response to the channel:
    return $some_response
    
    ## ...or use $core and return nothing:
    $core->send_event( 'send_message',
      $msg->context,
      $msg->channel,
      $some_response
    );
    return
  }

For more complicated games, you may want to write a stand-alone plugin.

See L<Cobalt::Manual::Plugins>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

B<Roulette.pm> provided by B<Schroedingers_hat> @ irc.cobaltirc.org

=cut
