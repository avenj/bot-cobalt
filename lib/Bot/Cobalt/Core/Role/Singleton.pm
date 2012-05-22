package Bot::Cobalt::Core::Role::Singleton;
our $VERSION = '0.003';

use strictures 1;

use Moo::Role;

sub instance {
  my $class = shift;
  
  no strict 'refs';
  my $instance = \${$class.'::_instance'};
  
  return defined $$instance ?
    $$instance
    : ( $$instance = $class->new(@_) );
}

sub has_instance { is_instanced(@_) }
sub is_instanced {
  my $class = ref $_[0] || $_[0];
  no strict 'refs';
  return ${$class.'::_instance'}
}

1;
__END__
