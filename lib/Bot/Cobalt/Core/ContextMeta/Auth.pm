package Bot::Cobalt::Core::ContextMeta::Auth;
our $VERSION = '0.200_48';

use 5.10.1;
use strictures 1;

use Moo;
use Carp;

use Bot::Cobalt::Common qw/:types/;

extends 'Bot::Cobalt::Core::ContextMeta';

around 'add' => sub {
  my $orig = shift;
  my $self = shift;
  
  ## auth->add(
  ##   Context  => $context,
  ##   Username => $username,
  ##   Host     => $host,
  ##   Level    => $level,
  ##   Flags    => $flags,
  ##   Alias    => $plugin_alias
  ## )

  my %args = @_;
  
  $args{lc $_} = $args{$_} for keys %args;
  
  for my $required (qw/context nickname username host level/) {
    unless (defined $args{$required}) {
      carp "add() needs at least a Context, Username, Host, and Level";
      return
    }
  }
  
  $args{alias} = scalar caller unless $args{alias};
  $args{flags} = {}            unless $args{flags};
  
  my $meta = {
    Alias => $args{alias},
    Username => $args{username},
    Host  => $args{host},
    Level => $args{level},
    Flags => $args{flags},
  };

  $orig->($self, $args{context}, $args{nickname}, $meta);
};

sub level {
  my ($self, $context, $nickname) = @_;

  return 0 unless defined $context and defined $nickname;
  
  return 0 unless exists $self->_list->{$context}
         and ref $self->_list->{$context}->{$nickname};
  
  return $self->_list->{$context}->{$nickname}->{Level} // 0
}

sub flags {
  my ($self, $context, $nickname) = @_;

  return unless exists $self->_list->{$context}
         and ref $self->_list->{$context}->{$nickname}
         and ref $self->_list->{$context}->{$nickname}->{Flags} eq 'HASH';

  return $self->_list->{$context}->{$nickname}->{Flags}
}

sub username {
  my ($self, $context, $nickname) = @_;
  
  return unless defined $context and defined $nickname;
  
  return unless exists $self->_list->{$context}
         and ref $self->_list->{$context}->{$nickname};

  return $self->_list->{$context}->{$nickname}->{Username}
}

sub host {
  my ($self, $context, $nickname) = @_;
  
  return unless defined $context and defined $nickname;
  
  return unless exists $self->_list->{$context}
         and ref $self->_list->{$context}->{$nickname};

  return $self->_list->{$context}->{$nickname}->{Host}
}

sub alias {
  my ($self, $context, $nickname) = @_;
  return unless defined $context and defined $nickname;
  
  return unless exists $self->_list->{$context}
         and ref $self->_list->{$context}->{$nickname};

  return $self->_list->{$context}->{$nickname}->{Alias}
}

sub move {
  my ($self, $context, $old, $new) = @_;
  ## User changed nicks, f.ex
  
  return unless exists $self->_list->{$context}->{$old};
  ## FIXME check auth 'ownership' ... ?
  
  $self->core->log->debug("Adjusting auth nicks; $old -> $new");
  
  $self->_list->{$context}->{$new} =  
    delete $self->_list->{$context}->{$old};
}


1;
