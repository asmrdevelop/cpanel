package Cpanel::Exception::Database::UserNotFound;

# cpanel - Cpanel/Exception/Database/UserNotFound.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Metadata parameters:
#   name - required
#   engine - required, "mysql" or "postgresql"
#   cpuser - optional
#
sub _default_phrase {
    my ($self) = @_;

    if ( length $self->get('cpuser') ) {
        my @mt_args = map { $self->get($_) } qw(cpuser name);

        if ( $self->get('engine') eq 'mysql' ) {
            return Cpanel::LocaleString->new( 'The system user “[_1]” does not control a MySQL user named “[_2]”.', @mt_args );
        }
        elsif ( $self->get('engine') eq 'postgresql' ) {
            return Cpanel::LocaleString->new( 'The system user “[_1]” does not control a PostgreSQL user named “[_2]”.', @mt_args );
        }
    }
    else {
        my @mt_args = ( $self->get('name') );

        if ( $self->get('engine') eq 'mysql' ) {
            return Cpanel::LocaleString->new( 'You do not control a MySQL user named “[_1]”.', @mt_args );
        }
        elsif ( $self->get('engine') eq 'postgresql' ) {
            return Cpanel::LocaleString->new( 'You do not control a PostgreSQL user named “[_1]”.', @mt_args );
        }
    }

    die "Unknown DB engine: " . $self->get('engine');
}

1;
