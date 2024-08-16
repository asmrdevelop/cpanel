<?php 
/**
*  This plugin performs automated autentication for cPanel's Webmail
*/
class cpanellogout extends rcube_plugin
{
  public $task = 'logout';

  function init()
  {
    $this->add_hook('logout_after', array($this, 'logout_after'));
  } 

  function logout_after($args) 
  {
    // cpanel 32637: VACUUM on logout if using a sqlite database
    $sqlite = 'sqlite:///';
    if ( !empty($config['db_dsnw']) && strncmp($config['db_dsnw'], $sqlite, strlen($sqlite)) == 0 ) {
      $db = $this->get_dbh();
      $db->query("VACUUM");
    }
    header('Location: /webmaillogout.cgi');
    return $args;
  }

}

?>
