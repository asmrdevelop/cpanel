package Cpanel::Config::Contact;

# cpanel - Cpanel/Config/Contact.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Hostname                ();

$Cpanel::Config::Contact::VERSION = '1.0';

sub get_server_contact { return _get_contact('SERVERCONTACTEMAIL'); }

sub get_public_contact { return _get_contact('PUBLICCONTACTEMAIL'); }

sub _get_contact {
    my $key  = shift;
    my $conf = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    if ( exists $conf->{$key} && $conf->{$key} ) {
        return $conf->{$key};
    }
    elsif ( exists $conf->{'CONTACTEMAIL'} && $conf->{'CONTACTEMAIL'} ) {
        return $conf->{'CONTACTEMAIL'};
    }
    my $host = Cpanel::Hostname::gethostname();
    return 'root@' . $host;
}

sub get_server_pager {
    my $conf = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    if ( exists $conf->{'CONTACTPAGER'} && $conf->{'CONTACTPAGER'} ) {
        return $conf->{'CONTACTPAGER'};
    }
    return '';
}

1;
