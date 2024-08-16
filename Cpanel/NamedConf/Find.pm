package Cpanel::NamedConf::Find;

# cpanel - Cpanel/NamedConf/Find.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Moved to Cpanel::NameServer::Utils::BIND
use Cpanel::NameServer::Utils::BIND ();

our $VERSION = '1.1';

sub find_namedconf {
    goto &Cpanel::NameServer::Utils::BIND::find_namedconf;
}

sub checknamedconf {
    goto &Cpanel::NameServer::Utils::BIND::checknamedconf;
}

sub find_chrootbinddir {
    goto &Cpanel::NameServer::Utils::BIND::find_chrootbinddir;
}

1;
