package Bot::Cobalt::Plugin::Extras::Logger;
our $VERSION = '0.200_46';

## FIXME
##  - push ourselves up towards right after Bot::Cobalt::IRC
##  (core method to do so easily?)
## configurable logging:
##  - configurable log type, support mirc / eggdrop style?
##  - configurable path format including directories (attempt to mkpath if needed)
##  - configurable directory and file permissions?
##  - log relative to var/ unless absolute path? File::Spec->file_name_is_absolute
##  - configurable log notices from user to console / per-user / consolidated
##  - same for privmsgs? be sure to note that logging privmsgs reveals passwds
##  - per chan/context:
##   - type/class: 'all', 'chanevent', 'public', 'private', 'outgoing'
##      private has to be context-wide
##      console.log for unspecific stuff
##      public/private implies outgoing also
##      ability to combine above arbitrarily
use 5.10.1;
use Bot::Cobalt::Common;

use File::Path;
use File::Spec;
use Fcntl qw/:flock/;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  $self->{Buffers} = { };
  
  $core->plugin_register( $self, 'SERVER',
    [
      'connected',
      'disconnected',
      'server_error',
      
      'chan_sync',
      
      'topic_changed',
      'mode_changed',
      
      'user_joined',
      'user_quit',
      'user_left',
      'self_left',
      'user_kicked',
      'self_kicked',
      'nick_changed',
      'invited',
      
      'public_msg',
      'private_msg',
      'notice',
      'ctcp_action',
      
      'message_sent',
      'notice_sent',
      'ctcp_sent',
      
      'logger_flushbuffers',
    ]
  );
  
  $core->log->info("Loaded logger");
  
  $core->timer_set( 10,
    {
      Event => 'logger_flushbuffers',
    },
    'LOGGER_FLUSHBUF'
  );
  
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unloaded");
  return PLUGIN_EAT_NONE
}

sub Bot_connected {

}

sub Bot_disconnected {

}

sub Bot_server_error {

}

sub Bot_chan_sync {

}

sub Bot_topic_changed {

}

sub Bot_mode_changed {

}

sub Bot_user_joined {

}

sub Bot_user_left {

}

sub Bot_self_left {

}

sub Bot_user_kicked {

}

sub Bot_self_kicked {

}

sub Bot_nick_changed {

}

sub Bot_invited {

}

sub Bot_public_msg {

}

sub Bot_private_msg {

}

sub Bot_notice {

}

sub Bot_ctcp_action {

}

sub Bot_message_sent {

}

sub Bot_notice_sent {

}

sub Bot_ctcp_sent {

}


sub Bot_logger_flushbuffers {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME
  ## timed event
  ## hash of paths and lines to write?
  ## locking? skip and wait for next run if locked
  
  $core->timer_set( 10,
    {
      Event => 'logger_flushbuffers',
    },
    'LOGGER_FLUSHBUF'
  );
  
  return PLUGIN_EAT_ALL
}


sub log_to_console {
  my ($self, $context) = @_;
#  my $buf = $self->{Buffers}; 
}

sub log_to_other {
  my ($self, $context, $relpath) = @_;
  
}

sub log_to_channel {
  my ($self, $context, $channel) = @_;
  
}

sub log_to_private {
  my ($self, $context, $nickname) = @_;

}

1;
__END__

=pod

FIXME

=cut
