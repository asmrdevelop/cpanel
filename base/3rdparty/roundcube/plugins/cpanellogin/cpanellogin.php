<?php

// Lock out roundcube during updates.
if ( file_exists('/var/cpanel/roundcube/updating') ) {
    $ERROR_MESSAGE = 'Roundcube is in the process of being updated.';
    raise_error(
        array (
            'code' => 800,
            'type' => 'php',
            'message' => 'Roundcube is in the process of being updated.',
            'line' => __LINE__,
            'file' => __FILE__,
        ),
        true,
        true
    );
}

/**
*  This plugin performs automated autentication for cPanel's Webmail
*/
class cpanellogin extends rcube_plugin
{
  public $task = 'login';

  function init()
  {
    $this->add_hook('startup', array($this, 'startup'));
    $this->add_hook('authenticate', array($this, 'authenticate'));
  } 

  function startup($args)
  {
    $rcmail = rcmail::get_instance();
    // change action to login
    if (empty($_SESSION['user_id']) )
      $args['action'] = 'login';
    return $args;
  }

  function authenticate($args)
  {
    $args['user'] = $_ENV['REMOTE_USER'];
    $args['pass'] = $_ENV['REMOTE_PASSWORD'];
    $args['host'] = 'localhost';
    return $args;
  }
}

?>
