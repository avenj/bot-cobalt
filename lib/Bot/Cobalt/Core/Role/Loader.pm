package Bot::Cobalt::Core::Role::Loader;
our $VERSION = '0.010_01';

use 5.10.1;
use strict;
use warnings;

use Moo::Role;

use Scalar::Util qw/blessed/;

use Try::Tiny;

requires qw/
  cfg
  debug
  log
  send_event
  State
/;


sub is_reloadable {
  my ($self, $alias, $obj) = @_;

  if ($obj and ref $obj) {
    ## passed an object
    ## see if the object is marked non-reloadable
    ## if it is, update State
    if ( $obj->{NON_RELOADABLE} ||
       ( $obj->can("NON_RELOADABLE") && $obj->NON_RELOADABLE() )
    ) {

      $self->log->debug("Marked plugin $alias non-reloadable");

      $self->State->{NonReloadable}->{$alias} = 1;

      ## not reloadable, return 0
      return
    } else {
      ## reloadable, return 1
      delete $self->State->{NonReloadable}->{$alias};

      return 1
    }
  }
  ## passed just an alias (or a bustedass object)
  ## return whether the alias is reloadable
  return if $self->State->{NonReloadable}->{$alias};

  return 1
}

sub load_plugin {
  my ($self, $alias) = @_;
  
  my $plugins_cf = $self->cfg->{plugins};
  
  my $module = $plugins_cf->{$alias}->{Module};
  
  unless (defined $module) {
    ## Shouldn't happen unless someone's been naughty.
    ## Conf.pm checks for missing 'Module' at load-time.
    $self->log->error("Missing Module directive for $alias");
    return
  }

  my $modpath = join( '/', split /(?:'|::)/, $module ) . '.pm';

  my $orig_err;
  unless (try { require $modpath;1 } catch { $orig_err = $_;0 } ) {
    $self->log->error(
      "Could not load $module: $orig_err"
    );
    return
  }

  my $obj;
  try 
    { $obj = $module->new(); } 
  catch {
     $self->log->error(
       "new() failed for $module: $_"
     ); 0
  } or return;
  
  $self->is_reloadable($alias, $obj);

  return $obj
}

sub unloader_cleanup {
  ## clean up symbol table after a module load fails miserably
  ## (or when unloading)
  my ($self, $module) = @_;

  $self->log->debug("cleaning up after $module (unloader_cleanup)");

  my $included = join( '/', split /(?:'|::)/, $module ) . '.pm';

  $self->log->debug("removing from INC: $included");
  delete $INC{$included};

  { no strict 'refs';

    @{$module.'::ISA'} = ();
    my $s_table = $module.'::';
    for my $symbol (keys %$s_table) {
      next if $symbol =~ /\A[^:]+::\z/;
      delete $s_table->{$symbol};
    }

  }

  $self->log->debug("finished module cleanup");
  return 1
}


1;
__END__
## FIXME correct pod
=pod

=head1 NAME

Bot::Cobalt::Core::Role::Loader - Plugin (un)load role for Bot::Cobalt

=head1 SYNOPSIS

  ## Load a plugin (returns object)
  my $obj = $core->load_plugin($alias);

  ## Clean a package from the symbol table
  $core->unloader_cleanup($package);

  ## Check NON_RELOADABLE State of a plugin
  $core->is_reloadable($alias);

  ## Update NON_RELOADABLE State of a plugin
  ## (usually at load-time)
  $core->is_reloadable($alias, $obj)

=head1 DESCRIPTION

This is a L<Moo::Role> consumed by L<Bot::Cobalt::Core>.

These methods are used by plugin managers such as 
L<Bot::Cobalt::Plugin::PluginMgr> to handle plugin load / unload / 
reload.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
