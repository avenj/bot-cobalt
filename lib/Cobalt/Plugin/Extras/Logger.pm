package Cobalt::Plugin::Extras::Logger;
our $VERSION = '0.001';

## FIXME
## configurable logging:
##  - configurable format including directories (attempt to mkpath if needed)
##  - configurable directory and file permissions?
##  - log relative to var/ unless absolute path? File::Spec->file_name_is_absolute
##  - per chan/context:
##   - type/class: 'all', 'chanevent', 'public', 'private', 'outgoing'
##      public/private implies outgoing
##      ability to combine above arbitrarily

use Cobalt::Common;

use File::Path;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  
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
    ]
  );
  
  $core->log->info("Loaded ($VERSION)");
  
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unloaded");
  return PLUGIN_EAT_NONE
}


1;
__END__

=pod

FIXME

=cut
