package Cpanel::HttpUtils::Conf;

# cpanel - Cpanel/HttpUtils/Conf.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Hostname           ();
use Cpanel::Config::LoadConfig ();

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';

our $VERSION = '1.1';

my $PRODUCT_CONF_DIR = '/var/cpanel';

my $_moddirdomains_conf;

sub fetchdirprotectconf {
    my ($domain) = @_;

    $_moddirdomains_conf ||= Cpanel::Config::LoadConfig::loadConfig( "$PRODUCT_CONF_DIR/moddirdomains", undef, ':' );
    my $dirusers = $_moddirdomains_conf->{$domain} || '';
    if ( $dirusers ne '-1' ) {
        return ( 1, $dirusers );
    }
    else {
        return ( 0, '' );
    }
}

my $_phpopendomains_conf;

sub fetchphpopendirconf {
    my ( $user, $domain ) = @_;

    $_phpopendomains_conf ||= Cpanel::Config::LoadConfig::loadConfig( "$PRODUCT_CONF_DIR/phpopendomains", undef, ':' );
    my $phpopen = $_phpopendomains_conf->{$domain} || '';

    return ( $phpopen ne '-1' ) ? 1 : 0;
}

sub get_main_server_name {
    require Cpanel::Config::LoadWwwAcctConf;
    my $wwwacct       = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    my $main_hostname = exists $wwwacct->{'HOST'} && $wwwacct->{'HOST'} ? $wwwacct->{'HOST'} : Cpanel::Hostname::gethostname();
    return $main_hostname;
}

sub get_main_server_admin {
    require Cpanel::Config::Contact;
    my $contact = Cpanel::Config::Contact::get_public_contact();
    $contact =~ s/,.+$//g;
    if ( $contact =~ m/^\s*(\S+)\s*.*/ ) {
        $contact = $1;
    }
    if ( !$contact ) {
        $contact = 'nobody@' . get_main_server_name();
    }
    return $contact;
}

sub default_product_dir {
    $PRODUCT_CONF_DIR = shift if @_;
    return $PRODUCT_CONF_DIR;
}

1;
