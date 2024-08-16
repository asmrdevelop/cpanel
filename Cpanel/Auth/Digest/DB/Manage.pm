package Cpanel::Auth::Digest::DB::Manage;

# cpanel - Cpanel/Auth/Digest/DB/Manage.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Auth::Digest::DB                    ();
use Cpanel::Auth::Digest::Realm                 ();
use Cpanel::Transaction::File::LoadConfig       ();
use Cpanel::Transaction::File::LoadConfigReader ();
use Cpanel::LoadModule                          ();

my @DEFAULT_OBJECT_PARAMS = ( 'delimiter' => ':', 'permissions' => 0640 );

#NOTE: Errors are published to $@.
sub remove_entry {
    my ($user) = @_;

    # Most of the time we won't have an entry for the
    # user so we can avoid reading the database
    # under a lock if has_entry returns false
    return 0 if !has_entry($user);
    if ( my $pwdb = _create_rw_object_if_exists() ) {
        $pwdb->remove_entry($user);

        my ( $status, $err ) = $pwdb->save_and_close();
        $@ = $err if !$status;
        return $status;
    }
    return 0;
}

#NOTE: Errors are published to $@.
sub get_entry {
    my ($user) = @_;
    if ( my $pwdb = _create_ro_object() ) {
        return $pwdb->get_entry($user);
    }
    return '';
}

#NOTE: Errors are published to $@.
sub has_entry {
    my ($user) = @_;
    if ( my $pwdb = _create_ro_object() ) {
        return $pwdb->has_entry($user) || 0;
    }
    return 0;
}

#NOTE: Errors are published to $@.
sub set_entry {
    my ( $user, $entry ) = @_;
    if ( my $pwdb = _create_rw_object() ) {
        $pwdb->set_entry( $user, $entry );

        my ( $status, $err ) = $pwdb->save_and_close();
        $@ = $err if !$status;
        return $status;
    }
    return 0;

}

sub set_password {
    my ( $user, $pass ) = @_;

    Cpanel::LoadModule::load_perl_module('Digest::MD5');
    my $realm = Cpanel::Auth::Digest::Realm::get_realm();
    my $entry = Digest::MD5::md5_hex("$user:$realm:$pass");

    return set_entry( $user, $entry );
}

#NOTE: Errors are published to $@.
sub lock {
    my ($user) = @_;
    if ( my $pwdb = _create_rw_object() ) {
        my $entry = $pwdb->get_entry($user);
        $entry =~ s/^\*LOCKED\*//g;
        $entry = '*LOCKED*' . $entry;
        $pwdb->set_entry( $user, $entry );

        my ( $status, $err ) = $pwdb->save_and_close();
        $@ = $err if !$status;
        return $status;
    }
    return 0;
}

#NOTE: Errors are published to $@.
sub unlock {
    my ($user) = @_;
    if ( my $pwdb = _create_rw_object() ) {
        my $entry = $pwdb->get_entry($user);
        $entry =~ s/^\*LOCKED\*//g;
        $pwdb->set_entry( $user, $entry );

        my ( $status, $err ) = $pwdb->save_and_close();
        $@ = $err if !$status;
        return $status;
    }
    return 0;
}

sub _create_rw_object_if_exists {
    return eval {
        Cpanel::Transaction::File::LoadConfig->new(
            @DEFAULT_OBJECT_PARAMS,
            path          => $Cpanel::Auth::Digest::DB::file,
            sysopen_flags => 0,
        );
    };
}

sub _create_rw_object {
    my $pwdb = eval { Cpanel::Transaction::File::LoadConfig->new( @DEFAULT_OBJECT_PARAMS, 'path' => $Cpanel::Auth::Digest::DB::file ) };
    return $pwdb;
}

sub _create_ro_object {
    my $pwdb = eval { Cpanel::Transaction::File::LoadConfigReader->new( @DEFAULT_OBJECT_PARAMS, 'path' => $Cpanel::Auth::Digest::DB::file ) };
    return $pwdb;
}

1;
