package Cpanel::DBI::ConnectUsesHash;

# cpanel - Cpanel/DBI/ConnectUsesHash.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A base class. Do not call or instantiate directly.
#----------------------------------------------------------------------

use strict;

use DBI         ();
use Cpanel::DBI ();    # for perlcc

use parent qw( Cpanel::DBI DBI );    # multi-level for perlcc

sub connect {
    my ( $class, $attrs_hr ) = @_;

    die 'Pass in a hashref.' if ref $attrs_hr ne 'HASH';

    #Important to normalize db/dbname etc. so that clone()
    #will override "db" over an existing "dbname" etc.
    my %store_attrs = %$attrs_hr;
    $class->normalize_attributes( \%store_attrs );

    #Copy since we're going to mutate...
    my %connect_attrs = %store_attrs;

    #TODO: File RTs about these not working in DBD::Pg.
    my ( $username, $password ) = delete @connect_attrs{qw(Username  Password)};

    my $dbh = $class->_connect( $username, $password, \%connect_attrs );

    $dbh->_set( '_attr_hr', \%store_attrs );

    return $dbh;
}

*dbi_connect = *Cpanel::DBI::connect;

use constant _database_keys => qw( database  dbname  db );

use constant _host_keys => qw( host  hostname );

use constant _mysql_socket_keys => qw( mysql_socket  socket );

use constant _port_keys => qw(port mysql_port);

sub normalize_attributes {
    my ( $class, $attrs_hr ) = @_;

    for my $key (qw( database  host mysql_socket port )) {
        my @possible_keys = $class->can("_${key}_keys")->($class);

        my @existent_keys = grep { exists $attrs_hr->{$_} } @possible_keys;

        die ">1 key (@existent_keys) for “$key”!" if @existent_keys > 1;

        if (@existent_keys) {
            $attrs_hr->{$key} = delete $attrs_hr->{ $existent_keys[0] };
        }
    }

    return;
}

1;
