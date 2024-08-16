package Cpanel::Mysql::ApiCompatibility;

# cpanel - Cpanel/Mysql/ApiCompatibility.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context       ();
use Cpanel::LoadModule    ();
use Cpanel::Encoder::Tiny ();

sub format_db_maintenance {
    my ( $dbname, @rows ) = @_;

    Cpanel::Context::must_be_list();

    return map { Cpanel::Encoder::Tiny::safe_html_encode_str("[$dbname.$_->[0]] $_->[1]: $_->[2]\n") } @rows;
}

#Pre-UAPI cPanel API calls expected stuff like "SHOWVIEW"
#rather than "SHOW VIEW". (It was a workaround for the admin layer’s
#inability to transmit arguments with spaces.)
#
#This function is the logic that those API calls implemented.
#
sub convert_legacy_privs_to_standard {
    my @PRIVS = @_;

    Cpanel::Context::must_be_list();

    my @SECUREPRIVS;

    foreach my $priv (@PRIVS) {
        if ( $priv =~ m/alterroutine/i ) {
            push @SECUREPRIVS, 'ALTER ROUTINE';
        }
        elsif ( $priv =~ m/alter/i ) {
            push( @SECUREPRIVS, 'ALTER' );
        }
        elsif ( $priv =~ m/temporary/i ) {
            push( @SECUREPRIVS, 'CREATE TEMPORARY TABLES' );
        }
        elsif ( $priv =~ m/routine/i ) {
            push( @SECUREPRIVS, 'CREATE ROUTINE' );
        }
        elsif ( $priv =~ m/execute/i ) {
            push( @SECUREPRIVS, 'EXECUTE' );
        }
        elsif ( $priv =~ m/createview/i ) {
            push( @SECUREPRIVS, 'CREATE VIEW' );
        }
        elsif ( $priv =~ m/showview/i ) {
            push( @SECUREPRIVS, 'SHOW VIEW' );
        }

        elsif ( $priv =~ m/trigger/i ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Mysql::Privs');
            Cpanel::Mysql::Privs::verify_privileges('TRIGGER');
            push( @SECUREPRIVS, 'TRIGGER' );
        }
        elsif ( $priv =~ m/create/i ) {
            push( @SECUREPRIVS, 'CREATE' );
        }
        elsif ( $priv =~ m/delete/i ) {
            push( @SECUREPRIVS, 'DELETE' );
        }
        elsif ( $priv =~ m/drop/i ) {
            push( @SECUREPRIVS, 'DROP' );
        }
        elsif ( $priv =~ m/event/i ) {
            push( @SECUREPRIVS, 'EVENT' );
        }
        elsif ( $priv =~ m/select/i ) {
            push( @SECUREPRIVS, 'SELECT' );
        }
        elsif ( $priv =~ m/insert/i ) {
            push( @SECUREPRIVS, 'INSERT' );
        }
        elsif ( $priv =~ m/update/i ) {
            push( @SECUREPRIVS, 'UPDATE' );
        }
        elsif ( $priv =~ m/references/i ) {
            push( @SECUREPRIVS, 'REFERENCES' );
        }
        elsif ( $priv =~ m/index/i ) {
            push( @SECUREPRIVS, 'INDEX' );
        }
        elsif ( $priv =~ m/lock/i ) {
            push( @SECUREPRIVS, 'LOCK TABLES' );
        }
        elsif ( $priv =~ m/all/i ) {
            @SECUREPRIVS = ('ALL');
            last;
        }
    }

    return @SECUREPRIVS;
}

1;
