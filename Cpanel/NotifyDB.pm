package Cpanel::NotifyDB;

# cpanel - Cpanel/NotifyDB.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::DataStore ();

our $VERSION = '0.1';

my %DBS;

sub loadnotify {
    my $user = shift;
    $user =~ s/\///g;
    my $dir = '/var/cpanel/notificationsdb';
    if ( !-e $dir ) {
        mkdir( $dir, 0700 );
    }

    $DBS{$user} = Cpanel::DataStore::fetch_ref( $dir . '/' . $user );
}

sub savenotify {
    my $user  = shift;
    my $key   = shift;
    my $value = shift || '1';
    $DBS{$user}->{$key} = $value;
}

sub clearnotify {
    my $user = shift;
    my $key  = shift;

    delete $DBS{$user}->{$key};
}

sub didnotify {
    my $user = shift;
    my $key  = shift;
    if ( ref $DBS{$user} eq 'HASH' && defined $DBS{$user}->{$key} ) {
        return 1;
    }
    return 0;
}

sub flushnotify {
    my $user = shift;
    $user =~ s/\///g;
    my $dir = '/var/cpanel/notificationsdb';
    if ( !-e $dir ) {
        mkdir( $dir, 0700 );
    }

    Cpanel::DataStore::store_ref( $dir . '/' . $user, $DBS{$user} );
    delete $DBS{$user};
}

1;
