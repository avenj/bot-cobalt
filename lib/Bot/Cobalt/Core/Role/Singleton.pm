package Bot::Cobalt::Core::Role::Singleton;
our $VERSION = '0.012';

use strictures 1;

use Moo::Role;

sub instance {
  my $class = shift;
  
  no strict 'refs';

  my $this_obj = \${$class.'::_singleton'};
  
  defined $$this_obj ?
    $$this_obj
    : ( $$this_obj = $class->new(@_) )
}

sub has_instance {
  my $class = ref $_[0] || $_[0];

  no strict 'refs';

  return unless ${$class.'::_singleton'};
  1
}

sub is_instanced {
  require Carp;
  Carp::confess("is_instanced is deprecated; use has_instance")
}

1;
__END__
