<?php

include("/usr/local/cpanel/php/cpanel.php");

$cpanel = new CPANEL();

print $cpanel->header();
print htmlentities( print_r( $cpanel->cpanelprint('This feature is disabled in demo mode.'), true ) );
print $cpanel->footer();

$cpanel->end();

?>
