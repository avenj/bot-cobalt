package Cobalt::Plugin::RDB::RPL;
our $VERSION = '0.20';

use 5.12.1;
use Moose;

use Cobalt::Utils qw/ rplprintf /;

##   my $rplf = Cobalt::Plugin::RDB::RPL->new(
##     ATTRIBUTE => VALUE
##   );
##   $rplf->reply($rpl);

has 'core' => (
  is  => 'ro',
  isa => 'Object',
  required => 1,
);

## Attributes used to feed RPLs:
has 'nick'    => ( is => 'rw', isa => 'Str', required => 1 );
has 'channel' => ( is => 'rw', isa => 'Str', default => "" );
has 'addedby' => ( is => 'rw', isa => 'Str', default => "" );
has 'content' => ( is => 'rw', isa => 'Str', default => "" );
has 'rdb'     => ( is => 'rw', isa => 'Str', default => "" );
has 'index'   => ( is => 'rw', isa => 'Str', default => "" );
has 'operation' => ( is => 'rw', isa => 'Str', default => "" );
has 'votedup'   => ( is => 'rw', isa => 'Str', default => "" );
has 'voteddown' => ( is => 'rw', isa => 'Str', default => "" );


sub reply {
  my ($self, $rpl) = @_;

  unless (defined $self->core->lang->{$rpl}) {
    $self->core->log->warn("Missing RPL: $rpl");
    return "Missing RPL: $rpl"
  }

  my $repl = rplprintf( $self->core->lang->{$rpl},
    nick => $self->nick,
    chan => $self->channel,
    op   => $self->operation,
    addedby => $self->addedby,
    content => $self->content,
    rdb   => $self->rdb,
    index => $self->index,
    votedup   => $self->votedup,
    voteddown => $self->voteddown,
  );

  return $repl || "$rpl";  
}

no Moose; 1;
