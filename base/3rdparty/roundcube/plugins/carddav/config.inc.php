<?php
$prefs['_GLOBAL']['suppress_version_warning'] = false;
$prefs['_GLOBAL']['sync_collection_workaround'] = false;
$domain = getenv('HTTP_HOST');
if( empty($domain) ) $domain = getenv('DOMAIN');
// Figure out the expected formatting based on username 
$userName = (string) $_SERVER['_RCUBE'];
$userFormat = (string) '%l@%d'; 
if( strpos($userName, '/') === false) { 
    $userFormat = '%l'; 
}
 
$prefs['cPCardDAV'] = array( 
   'name'     => 'cPanel CardDAV', 
   'username' => $userFormat, 
   'password' => '%p', 
   'url'      => 'https://127.0.0.1:2080/addressbooks/' . $userFormat . '/addressbook/',
   'active'   => true, 
   'fixed'    => array( 'name', 'username', 'password' ), 
   'hide'     => false, 
);

?>
