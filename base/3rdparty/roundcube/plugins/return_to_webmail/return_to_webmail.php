<?php

/**
* This plugin adds a button to return the user to the Webmail interface
**/

class return_to_webmail extends rcube_plugin
{

  function init()
  {
    // Add the button to the template
    $this->add_button(array(
      'command' => 'cpanel',
      'content' => 'Webmail Home',
      'class'   => 'button-cpwebmail',
      'classsel' => 'button-cpwebmail button-selected',
      'innerclass' => 'button-inner',
      'label'   => 'cpwebmail.cpwebmail',
      'type'    => 'link',
    ), 'taskbar');

    $this->add_button(array(
      'command' => 'purge',
      'content' => 'Empty',
      'class'   => 'button-cptrashempty',
      'classsel' => 'button-cptrashempty',
      'innerclass' => 'button-inner',
      'label'   => 'cptrashempty.cptrashempty',
      'type'    => 'link',
    ), 'listcontrols');

    // Include JS
    $this->include_script('return_to_webmail.js');

    // Include CSS
    $skin_path = $this->local_skin_path();
    $this->include_stylesheet($skin_path . '/return_to_webmail.css');
  }
}

?>
