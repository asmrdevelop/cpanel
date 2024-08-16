<html>
<pre>
<?php

include("/usr/local/cpanel/php/cpanel.php");

function print_r_html ( $data ) {
    print htmlentities( print_r( $data, true ) );
}

$cpanel = new CPANEL();

print_r_html ( $cpanel->exec('<cpanel print="cow">') );
print_r_html ( $cpanel->api1('print','',array('cow')) );
print_r_html ( $cpanel->exec('<cpanel setvar="debug=0">') );
print_r_html ( $cpanel->api('exec',1,'print','',array('cow')) );
print_r_html ( $cpanel->cpanelprint('$homedir') );
print_r_html ( $cpanel->cpanelprint('$hasvalidshell') );
print_r_html ( $cpanel->cpanelprint('$isreseller') );
print_r_html ( $cpanel->cpanelprint('$isresellerlogin') );
print_r_html ( $cpanel->exec('<cpanel Branding="file(local.css)">') );
print_r_html ( $cpanel->exec('<cpanel Branding="image(ftpaccounts)">') );
print_r_html ( $cpanel->api2('Email','listpopswithdisk',array('api2_paginate' => 1, 'api2_paginate_start' => 1, 'api2_paginate_size' => 10, "acct"=>1) ) ) ;
print_r_html ( $cpanel->fetch('$CPDATA{\'DNS\'}') );
print_r_html ( $cpanel->api2('Ftp','listftpwithdisk',array("skip_acct_types"=>'sub') ) );
print_r_html ( $cpanel->uapi('SSL','list_keys', array( 'api.sort_column' => 'friendly_name' )));
print_r_html ( $cpanel->uapi('non-exist','list_keys', array( 'api.sort_column' => 'friendly_name' )));
print_r_html ( $cpanel->api3('SSL','list_certs', array( 'api.sort_column' => 'subject.commonName', 'api.filter_column' => 'modulus', 'api.filter_term'  => 'mod_goes_here' ,'api.sort_column' => 'friendly_name' )));
print_r_html ( $cpanel->api2(array('Ftp' => 1),'listftpwithdisk',array("skip_acct_types"=>'sub') ) ); // should complain about an untrappable failure

if ( $cpanel->cpanelif('$haspostgres') ) { print "Postgres is installed\n"; }
if ( $cpanel->cpanelif('!$haspostgres') ) { print "Postgres is not installed\n"; }
if ($cpanel->cpanelfeature("fileman")) {
        print "The file manager feature is enabled\n";
}
print "test complete\n";
$cpanel->end();

?>
</pre>
</html>
