package Bot::Cobalt::Core::Loader;

use 5.12.1;
use strict;
use warnings FATAL => 'all';

use Carp;

use Scalar::Util qw/blessed/;

use Try::Tiny;

sub new { bless [], shift }

sub is_reloadable {
  my ($class, $obj) = @_;
  
  confess "is_reloadable() needs a plugin object"
    unless $obj and blessed $obj;
  
  return if $obj->can('NON_RELOADABLE') and $obj->NON_RELOADABLE;

  return 1
}

sub module_path {
  my ($class, $module) = @_;
  
  confess "module_path() needs a module name" unless defined $module;
  
  return join('/', split /::/, $module).".pm";
}

sub load {
  my ($class, $module) = @_;
  
  confess "load() needs a module name" unless defined $module;

  my $modpath = $class->module_path($module);

  my $orig_err;
  unless (try { require $modpath;1 } catch { $orig_err = $_;0 }) {
    ## die informatively
    croak "Could not load $module: $orig_err"
  }

  my $obj;
  try {
    $obj = $module->new()
  } catch {
    croak "new() failed for $module: $_"
  };
  
  $obj if blessed $obj
}

sub unload {
  my ($class, $module) = @_;
  
  confess "unload() needs a module name" unless defined $module;
  
  my $modpath = $class->module_path($module);
  
  delete $INC{$modpath};
  
  {
    no strict 'refs';
    @{$module.'::ISA'} = ();
    
    my $s_table = $module.'::';
    for my $symbol (keys %$s_table) {
      next if $symbol =~ /^[^:]+::$/;
      delete $s_table->{$symbol}
    }
  }
  
  ## Pretty much always returns success, on the theory that
  ## we did all we could from here.
  return 1
}

1

## FIXME POD, t/
