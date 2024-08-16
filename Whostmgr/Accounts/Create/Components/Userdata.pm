package Whostmgr::Accounts::Create::Components::Userdata;

# cpanel - Whostmgr/Accounts/Create/Components/Userdata.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::Accounts::Create::Components::Userdata

=head1 SYNOPSIS

    use 'Whostmgr::Accounts::Create::Components::Userdata';
    ...

=head1 DESCRIPTION

This module writes out the top-level and per-domain userdata for our new user.
Also moves any non-directory out of the way, and creates the new user's homedir.

=cut

use cPstrict;

use parent 'Whostmgr::Accounts::Create::Components::Base';

use constant pretty_name => "Userdata";

use Cpanel::ConfigFiles::Apache     ();
use Cpanel::Config::userdata::Guard ();
use Cpanel::Config::userdata::Utils ();
use Cpanel::ConfigFiles::Apache     ();
use Cpanel::Config::Httpd::IpPort   ();
use Cpanel::HttpUtils::Conf         ();

sub _run ( $output, $user = {} ) {
    my $guard    = Cpanel::Config::userdata::Guard->new( $user->{'user'} );
    my $userdata = $guard->data();
    $userdata->{'main_domain'} = $user->{'domain'};

    # the cp_php_magic_include_path.conf is at the user level
    if ( $user->{'_cpconf'}{'magicloader_php-pear'} ) {
        $userdata->{'cp_php_magic_include_path.conf'} = 1;
    }

    Cpanel::Config::userdata::Utils::sanitize_main_userdata($userdata);

    my $domain_guard = Cpanel::Config::userdata::Guard->new( $user->{'user'}, $user->{'domain'}, { main_data => $userdata } );
    my $ud_domain    = $domain_guard->data();
    $ud_domain->{'user'}                  = $user->{'user'};
    $ud_domain->{'group'}                 = getgrgid( $user->{'gid'} );
    $ud_domain->{'owner'}                 = $user->{'owner'};
    $ud_domain->{'hascgi'}                = $user->{'hascgi'} eq 'n' ? 0 : 1;
    $ud_domain->{'servername'}            = $user->{'domain'};
    $ud_domain->{'serveralias'}           = join( q{ }, map { $_ . $user->{'domain'} } qw( mail. www. ) );
    $ud_domain->{'usecanonicalname'}      = 'Off';
    $ud_domain->{'documentroot'}          = "$user->{'homedir'}/public_html";
    $ud_domain->{'homedir'}               = $user->{'homedir'};
    $ud_domain->{'port'}                  = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    $ud_domain->{'ip'}                    = $user->{'ip'};
    $ud_domain->{'serveradmin'}           = 'webmaster@' . $user->{'domain'};
    $ud_domain->{'phpopenbasedirprotect'} = Cpanel::HttpUtils::Conf::fetchphpopendirconf( $user->{'user'}, $user->{'domain'} );
    $ud_domain->{'customlog'}             = [
        { 'format' => 'combined',                    'target' => Cpanel::ConfigFiles::Apache::apache_paths_facade()->dir_domlogs() . "/$user->{'domain'}" },
        { 'format' => '"%{%s}t %I .\\n%{%s}t %O ."', 'target' => Cpanel::ConfigFiles::Apache::apache_paths_facade()->dir_domlogs() . "/$user->{'domain'}-bytes_log" },
    ];
    $ud_domain->{'scriptalias'} = [ { 'path' => "$user->{'homedir'}/public_html/cgi-bin", 'url' => '/cgi-bin/' }, ];

    $domain_guard->save();

    $guard->save();

    return 1;
}

1;
