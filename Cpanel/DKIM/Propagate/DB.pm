package Cpanel::DKIM::Propagate::DB;

# cpanel - Cpanel/DKIM/Propagate/DB.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::SQLite::AutoRebuildSchemaBase );

=encoding utf-8

=head1 NAME

Cpanel::DKIM::Propagate::DB

=head1 SYNOPSIS

    # Will rebuild the db if it has become corrupt
    my $dbh = Cpanel::DKIM::Propagate::DB->dbconnect();

    # Will NOT rebuild the db
    $dbh = Cpanel::DKIM::Propagate::DB->dbconnect_no_rebuild();

=head1 DESCRIPTION

Storage for propagation of DKIM keys to mail worker nodes.

=cut

#overridden in tests
our $_PATH;

BEGIN {
    $_PATH = '/var/cpanel/domain_keys/propagations.sqlite';
}

use constant {
    _SCHEMA_NAME => 'dkim_propagations',

    _SCHEMA_VERSION => 1,
};

sub _PATH {
    return $_PATH;
}

1;
