package Bot::Cobalt::Core::Role::EasyAccessors;
our $VERSION = '0.002';

use strictures 1;
use Moo::Role;

requires qw/
  cfg
  log
  PluginObjects
/;

use Storable qw/dclone/;

use Scalar::Util qw/blessed/;

sub get_plugin_alias {
  my ($self, $plugobj) = @_;
  return unless blessed $plugobj;
  my $alias = $self->PluginObjects->{$plugobj} || undef;
  return $alias
}

sub get_core_cfg {
  my ($self) = @_;
  my $corecfg = dclone( $self->cfg->{core} );
  return $corecfg
}

sub get_channels_cfg {
  my ($self, $context) = @_;
  unless ($context) {
    $self->log->warn(
      "get_channels_cfg called with no context at "
       .join ' ', (caller)[0,2]
    );
    return
  }
  ## Returns empty hash if there's no conf for this context:
  my $clonable = $self->cfg->{channels}->{$context};
  $clonable = {} unless $clonable and ref $clonable eq 'HASH';
  
  ## Per-channel configuration should be a hash
  ## (even if someone's been naughty with the ->cfg hash)
  for my $channel (keys %$clonable) {
    $clonable->{$channel} = {} unless ref $clonable->{$channel} eq 'HASH';
  }
  
  my $chcfg = dclone($clonable);
  
  return $chcfg
}

sub get_plugin_cfg {
  my ($self, $plugin) = @_;
  ## my $plugcf = $core->get_plugin_cfg( $self )
  ## Returns undef if no cfg was found

  my $alias;

  if (blessed $plugin) {
    ## plugin obj (theoretically) specified
    $alias = $self->PluginObjects->{$plugin};
    unless ($alias) {
      $self->log->error("No alias for $plugin");
      return
    }
  } else {
    ## string alias specified
    $alias = $plugin;
  }

  unless ($alias) {
    $self->log->error("get_plugin_cfg: no plugin alias? ".scalar caller);
    return
  }

  ## Return empty hash if there is no loaded config for this alias
  my $plugin_cf = $self->cfg->{plugin_cf}->{$alias} // return {};

  unless (ref $plugin_cf eq 'HASH') {
    $self->log->debug("get_plugin_cfg; $alias cfg not a HASH");
    return
  }

  ## return a copy, not a ref to the original.
  ## that way we can worry less about stupid plugins breaking things
  my $cloned = dclone($plugin_cf);
  return $cloned
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core::Role::EasyAccessors - Easy configuration accessors

=head1 SYNOPSIS

  ## Inside a Cobalt plugin
  my $current_alias = $core->get_plugin_alias($self);

  my $chan_cf_hash = $core->get_channels_cfg($context);
  
  my $plugin_cf = $core->get_plugin_cfg($self);
  
  my $core_cf = $core->get_core_cfg;
  
=head1 DESCRIPTION

Simple methods for accessing some of the configuration state tracked by 
L<Bot::Cobalt::Core>.

You might prefer L<Bot::Cobalt::Core::Sugar> when writing plugins.

=head2 get_plugin_alias

Takes an object (or a stringified object, but this happens 
automatically) and returns the registered alias for the plugin if it is 
loaded.

=head2 get_channels_cfg

Returns a copy of the channel configuration hash for the specified 
context.

=head2 get_plugin_cfg

Retrieves the current configuration hash for the specified plugin.

Takes either a plugin object (as a reference only) or a plugin alias (as 
a string).

=head2 get_core_cfg

Returns a copy of the 'core' configuration hash.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
