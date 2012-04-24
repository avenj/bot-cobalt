package Cobalt::Core::Role::Timers;

use 5.10.1;
use strict;
use warnings;
use Moo::Role;

use Cobalt::Timer;

requires qw/
  log
  debug
  send_event
/;

has TimerPool => ( is => 'rw', default => quote_sub q{ {} });

sub timer_set {
  ## FIXME: support either old-style hashref (create Cobalt::Timer)
  ## or passed-in Cobalt::Timer
  ## changeup core to use Cobalt::Timer ->execute methods

  my ($self, $delay, $ev, $id) = @_;

  unless (ref $ev eq 'HASH') {
    $self->log->warn("timer_set not called with hashref in ".caller);
    return
  }

  ## automatically pick a unique id unless specified
  if ($id) {
    ## an id was specified, overrule any existing by the same name
    delete $self->TimerPool->{$id};
  } else {
    my @p = ( 'a'..'f', 0..9 );
    $id = join '', map { $p[rand@p] } 1 .. 4;
    $id .= $p[rand@p] while exists $self->TimerPool->{$id};
  }

  ## Try to guess type, or default to 'event'
  my $type = $ev->{Type};
  unless ($type) {
    if (defined $ev->{Text} && defined $ev->{Context}) {
      $type = 'msg'
    } else {
      $type = 'event'
    }
  }
  
  
  my($event_name, @event_args);

  given ($type) {

    when ("event") {
      unless (exists $ev->{Event}) {
        $self->log->warn("timer_set no Event specified in ".caller);
        return
      }
      $event_name = $ev->{Event};
      @event_args = @{ $ev->{Args} // [] };
    }

    when ([qw/msg message privmsg action/]) {
      unless ($ev->{Text}) {
        $self->log->warn("timer_set no Text specified in ".caller);
        return
      }
      unless ($ev->{Target}) {
        $self->log->warn("timer_set no Target specified in ".caller);
        return
      }

      my $context = $ev->{Context} // 'Main';

      ## send_message / send_action $context, $target, $text
      $event_name = $type eq "action" ? 'send_action' : 'send_message' ;
      @event_args = ( $context, $ev->{Target}, $ev->{Text} );
    }
  }

  # tag w/ __PACKAGE__ if no alias is specified
  my $addedby = $ev->{Alias} // caller;

  if ($event_name) {
    $self->TimerPool->{$id} = {
      ExecuteAt => time() + $delay,
      Event   => $event_name,
      Args    => [ @event_args ],
      AddedBy => $addedby,
    };

    $self->send_event( 'new_timer', $id );

    $self->log->debug("timer_set; $id $delay $event_name")
      if $self->debug > 1;

    return $id

  } else {
    $self->log->debug("timer_set called but no timer added; bad type?");
    $self->log->debug("timer_set failure for ".join(' ', (caller)[0,2]) );
  }

  return
}

sub del_timer { timer_del(@_) }
sub timer_del {
  ## delete a timer by its ID
  ## doesn't care if the timerID actually exists or not.
  my ($self, $id) = @_;
  return unless $id;

  $self->log->debug("timer del; $id")
    if $self->debug > 1;

  return unless exists $self->TimerPool->{$id};

  my $deleted = delete $self->TimerPool->{$id};
  $self->send_event( 'deleted_timer', $id, $deleted );
  
  return $deleted
}

sub get_timer { timer_get(@_) }
sub timer_get {
  my ($self, $id) = @_;
  return unless $id;

  $self->log->debug("timer retrieved; $id")
    if $self->debug > 2;

  return $self->TimerPool->{$id}
}

sub timer_get_alias {
  ## get all timerIDs for this alias
  my ($self, $alias) = @_;
  return unless $alias;

  my $timerpool = $self->TimerPool;
  my @timers;

  for my $timerID (keys %$timerpool) {
    my $entry = $timerpool->{$timerID};
    push(@timers, $timerID) if $entry->{AddedBy} eq $alias;
  }

  return wantarray ? @timers : \@timers
}

sub timer_del_alias {
  my ($self, $alias) = @_;
  return $alias;
  my $timerpool = $self->TimerPool;

  my @deleted;

  for my $id (keys %$timerpool) {
    my $entry = $timerpool->{$id};

    if ($entry->{AddedBy} eq $alias) {
      my $deleted = delete $timerpool->{$id};
      push(@deleted, $id);
      $self->send_event( 'deleted_timer', $id, $deleted );
    }

  }

  return wantarray ? @deleted : scalar @deleted 
}


1;
__END__

=pod

=head1 NAME

Cobalt::Core::Role::Timers - A role for managing a timer pool

=head1 SYNOPSIS

  ## From a Cobalt plugin:
  my $new_id = $core->timer_set( 60,
    {
      Event => 'my_timed_event',
      Args  => [ $one, $two ],
      Alias => $core->get_plugin_alias($self),
    }
  );
  
  $core->timer_set( 60,
    {
      Event => 'my_timed_event',
      Args  => [ $one, $two ],
    },
    'MY_NAMED_TIMER'
  );
  
  $core->timer_del( $timer_id );
  $core->timer_del_alias( $core->get_plugin_alias($self) );
  
  my $timer_item = $core->timer_get( $timer_id );
  my @active = $core->timer_get_alias( $core->get_plugin_alias($self) );
    

=head1 DESCRIPTION

A Moo role for managing a pool of timers living in a TimerPool hash.

This is consumed by L<Cobalt::Core> to provide timer manipulation 
methods to the plugin pipeline.

=head1 METHODS

=head2 timer_set

The B<timer_set> method adds a new timer to the hashref 
provided by B<TimerPool> in the consumer class.

  $core->timer_set( $secs, $opts_ref );
  $core->timer_set( $secs, $opts_ref, $timer_id );

Timer options should be provided as a hash reference.

B<timer_set> will return the new timer's ID on success; a B<send_event> 
will be called for event L</new_timer>.

=head3 Basic timers

The most basic timer is fire-and-forget with no alias tag and no 
preservation of timer ID:

  ## From a Cobalt plugin
  ## Trigger Bot_myplugin_timed_ev with no args in 30 seconds
  $core->timer_set( 30, { Event => 'myplugin_timed_ev'  } );

A more sophisticated timer will probably have some arguments specified:

  $core->timer_set( 30,
    {
      Event => 'myplugin_timed_ev',
      Args  => [ $one, $two ],
    },
  );

If this is not a named timer, a unique timer ID will be created:

  my $new_id = $core->timer_set(30, { Event => 'myplugin_timed_ev' });

When used from Cobalt plugins, a timer should usually have an alias 
specified; this makes it easier to clear your pending timers from a 
B<Cobalt_unregister> event using L</timer_del_alias>, for example.

  ## From a Cobalt plugin
  ## Tag w/ our current plugin alias from Cobalt::Core
  my $new_id = $core->timer_set( 30,
    {
      Event => 'myplugin_timed_ev',
      Args  => [ $one, $two ],
      Alias => $core->get_plugin_alias($self),
    }
  );

=head3 Named timers

If a timer is intended to be globally unique within this TimerPool or 
the timer ID is generated by some other method, it can be specified in 
B<timer_set>. Existing timers with the same ID will be replaced.

  $core->timer_set( 30, 
    { 
      Event => 'myplugin_timed_ev',
      Args  => [ ],
    },
    'MY_NAMED_TIMER',
  );

(This, of course, makes life difficult if your plugin is intended to be 
instanced more than once.)

=head3 Message timers

If a timer is simply intended to send some message or action to an IRC 
context, the B<msg> and B<action> types can be used for convenience:

  $core->timer_set( 30,
    {
      Alias   => $core->get_plugin_alias($self),
      Type    => 'msg',
      Context => $context,
      Target  => $channel,
      Text    => $string,
    },
  );

=head2 timer_del

Deletes a timer by timer ID.

Returns the deleted timer item on success.

Calls a B<send_event> for event L</deleted_timer>.

=head2 timer_del_alias

Deletes a timer by tagged alias.

Returns the list of deleted timer IDs in list context or the number of 
deleted timers in scalar context.

A B<send_event> is called for L</deleted_timer> events for every 
removed timer.

=head2 timer_get

Rarely used.

Retrieves the reference to the specified timer ID.

This can be useful for tweaking active timers.

=head2 timer_get_alias

Returns all timer IDs belonging to the specified alias tag.

Returns a list of timer IDs. In scalar context, returns an array 
reference.

=head1 EVENTS

=head2 new_timer

Issued when a timer is set.

Only argument provided is the timer ID.

=head2 deleted_timer

Issued when a timer is deleted.

Arguments are the timer ID and the deleted item hash, respectively.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>


=cut
