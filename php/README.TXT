Input (must have the .livephp ext and reside in /usr/local/cpanel/base/frontend/*/...):
<?php

include("/usr/local/cpanel/php/cpanel.php");


$cpanel = &new CPANEL();
print_r  ( $cpanel->exec('<cpanel print="cow">') );
print_r  ( $cpanel->api1('print','',array('cow')) );
print_r  ( $cpanel->exec('<cpanel setvar="debug=0">') );
print_r  ( $cpanel->api('exec',1,'print','',array('cow')) );
print_r  ( $cpanel->cpanelprint('$homedir') );
print_r  ( $cpanel->cpanelprint('$hasvalidshell') );
print_r  ( $cpanel->cpanelprint('$isreseller') );
print_r  ( $cpanel->cpanelprint('$isresellerlogin') );
print_r  ( $cpanel->exec('<cpanel Branding="file(local.css)">') );
print_r  ( $cpanel->exec('<cpanel Branding="image(ftpaccounts)">') );
print_r  ( $cpanel->api2('Email','listpopswithdisk',array("acct"=>1) ) ) ;
print_r  ( $cpanel->fetch('$CPDATA{\'DNS\'}') );
print_r  ( $cpanel->api2('Ftp','listftpwithdisk',array("skip_acct_types"=>'sub') ) ) ;

if ( $cpanel->cpanelif('$haspostgres') ) { print "Postgres is installed\n"; }
if ( $cpanel->cpanelif('!$haspostgres') ) { print "Postgres is not installed\n"; }
if ($cpanel->cpanelfeature("fileman")) {
        print "The file manager feature is enabled\n";
}

$cpanel->end();

?>

Result:

Array
(
    [cpanelresult] => Array
        (
            [command] => print
            [type] => internal
            [source] => internal
            [apiversion] => 1
            [data] => Array
                (
                    [result] => cow
                )

        )

)
Array
(
    [cpanelresult] => Array
        (
            [command] => print
            [type] => internal
            [source] => internal
            [apiversion] => 1
            [data] => Array
                (
                    [result] => cow
                )

        )

)
Array
(
    [cpanelresult] => Array
        (
            [command] => setvar
            [type] => internal
            [source] => internal
            [apiversion] => 1
            [data] => Array
                (
                    [result] =>
                )

        )

)
Array
(
    [cpanelresult] => Array
        (
            [command] => print
            [type] => internal
            [source] => internal
            [apiversion] => 1
            [data] => Array
                (
                    [result] => cow
                )

        )

)
/home/nick011Array
(
    [cpanelresult] => Array
        (
            [module] => Branding
            [func] => file
            [type] => event
            [source] => module
            [apiversion] => 1
            [data] => Array
                (
                    [result] => /frontend/x3test/branding//local.css
                )

        )

)
Array
(
    [cpanelresult] => Array
        (
            [module] => Branding
            [func] => image
            [type] => event
            [source] => module
            [apiversion] => 1
            [data] => Array
                (
                    [result] => /frontend/x3test/branding//ftpaccounts.jpg
                )

        )

)
Array
(
    [cpanelresult] => Array
        (
            [apiversion] => 2
            [data] => Array
                (
                    [0] => Array
                        (
                            [_diskquota] => 10.00
                            [_diskused] => 0.00
                            [diskquota] => 10.00
                            [diskused] => 0.00
                            [diskusedpercent] => 0
                            [diskusedpercent20] => 0
                            [domain] => pi.nt
                            [email] => bob@pi.nt
                            [login] => bob@pi.nt
                            [txtdiskquota] => 10.00
                            [user] => bob
                        )

                    [1] => Array
                        (
                            [_diskquota] => 10.00
                            [_diskused] => 0.00
                            [diskquota] => 10.00
                            [diskused] => 0.00
                            [diskusedpercent] => 0
                            [diskusedpercent20] => 0
                            [domain] => pi.nt
                            [email] => lkl@pi.nt
                            [login] => lkl@pi.nt
                            [txtdiskquota] => 10.00
                            [user] => lkl
                        )

                )

            [func] => listpopswithdisk
            [module] => Email
        )

)
Array
(
    [cpanelresult] => Array
        (
            [command] => print
            [type] => internal
            [source] => internal
            [apiversion] => 1
            [data] => Array
                (
                    [result] => pi.nt
                )

        )

)
Array
(
    [cpanelresult] => Array
        (
            [apiversion] => 2
            [data] => Array
                (
                    [0] => Array
                        (
                            [_diskquota] => 4344.00
                            [_diskused] => 0.00
                            [accttype] => anonymous
                            [deleteable] => 0
                            [dir] => /home/nick/public_ftp
                            [diskquota] => 4344.00
                            [diskused] => 0.00
                            [diskusedpercent] => 0
                            [diskusedpercent20] => 0
                            [htmldir] =>
                            [login] => anonymous
                            [reldir] => public_ftp
                            [serverlogin] => anonymous@pi.nt
                        )

                    [1] => Array
                        (
                            [_diskquota] => 4344.00
                            [_diskused] => 0.00
                            [accttype] => anonymous
                            [deleteable] => 0
                            [dir] => /home/nick/public_ftp
                            [diskquota] => 4344.00
                            [diskused] => 0.00
                            [diskusedpercent] => 0
                            [diskusedpercent20] => 0
                            [htmldir] =>
                            [login] => ftp
                            [reldir] => public_ftp
                            [serverlogin] => ftp@pi.nt
                        )

                    [2] => Array
                        (
                            [_diskquota] => 0.00
                            [_diskused] => 0.00
                            [accttype] => main
                            [deleteable] => 1
                            [dir] => /home/nick
                            [diskquota] => unlimited
                            [diskused] => 0.00
                            [diskusedpercent] => 0
                            [diskusedpercent20] => 0
                            [htmldir] =>
                            [login] => nick
                            [reldir] =>
                            [serverlogin] => nick
                        )

                    [3] => Array
                        (
                            [_diskquota] => 0.00
                            [_diskused] => 0.00
                            [accttype] => logaccess
                            [deleteable] => 1
                            [dir] => /usr/local/apache/domlogs
                            [diskquota] => unlimited
                            [diskused] => 0.00
                            [diskusedpercent] => 0
                            [diskusedpercent20] => 0
                            [htmldir] =>
                            [login] => nick_logs
                            [reldir] => usr/local/apache/domlogs
                            [serverlogin] => nick_logs
                        )

                )

            [func] => listftpwithdisk
            [module] => Ftp
        )

)
Postgres is installed
The file manager feature is enabled


