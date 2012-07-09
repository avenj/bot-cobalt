package Bot::Cobalt::Conf::File::Plugins;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Bot::Cobalt::Common qw/:types/;

use Scalar::Util qw/blessed/;


extends 'Bot::Cobalt::Conf::File';



around 'validate' => sub {
  my ($orig, $self, $cfg) = @_;

  ## FIXME

  1
};

1;
__END__
