<?php
$config['address_book_type'] = 'sql';
$mandatory_plugins = ['cpanellogin','cpanellogout','archive','calendar','return_to_webmail','markasjunk','cpanelchecks','cpanelicsimport','cpanelvcfimport'];
if(!file_exists('/etc/cpdavddisable') && !file_exists('/etc/cpdavdisevil') ) {
    $mandatory_plugins[] = 'carddav';
}

foreach( $mandatory_plugins as $plugin ) {
    if(! preg_grep("/$plugin/",$config['plugins']) ) {
    	array_push($config['plugins'],$plugin);
    }
}

?>
