package Cpanel::Exception::Database::DatabaseMissing;

# cpanel - Cpanel/Exception/Database/DatabaseMissing.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This error is for when the DB map refers to a database that the
#DB server doesn't actually have. That shouldn't normally happen.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Metadata parameters:
#   name - required
#   engine - required, "mysql" or "postgresql"
#
sub _default_phrase {
    my ($self) = @_;

    if ( $self->get('engine') eq 'mysql' ) {
        return Cpanel::LocaleString->new( 'Although the system’s database map includes a MySQL database named “[_1]”, the MySQL server reported that no database with this name exists. Contact your system administrator.', $self->get('name') );
    }
    elsif ( $self->get('engine') eq 'postgresql' ) {
        return Cpanel::LocaleString->new( 'Although the system’s database map includes a PostgreSQL database named “[_1]”, the PostgreSQL server reported that no database with this name exists. Contact your system administrator.', $self->get('name') );
    }

    die "Unknown DB engine: " . $self->get('engine');
}

1;
