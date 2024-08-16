package Whostmgr::Passwd;

# cpanel - Whostmgr/Passwd.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings      ();
use Cpanel::Debug ();
use Cpanel::Rand  ();

use Try::Tiny;

our $token_dir = '/var/cpanel/passtokens';

sub generate_token {
    if ( !-d $token_dir ) {
        unlink $token_dir;
        mkdir $token_dir, 0700;
    }
    else {
        expire_tokens();
    }

    my $now = time;
    my ( $token_file, $token_FH ) = Cpanel::Rand::get_tmp_file_by_name( $token_dir . '/' . $now, 'token' );    # audit case 46806 ok
    if ($token_file) {
        close $token_FH;
        return substr( $token_file, length( $token_dir . '/' . $now . '.token.' ) );
    }

    Cpanel::Debug::log_warn("Failed to create token file: $!");
    return '';
}

sub verify_token {
    my ($token) = @_;
    return if ( !$token || $token =~ m/\// );

    my @tokens;
    if ( opendir my $dh, $token_dir ) {
        @tokens = readdir $dh;
        closedir $dh;
    }

    foreach my $token_file (@tokens) {
        next if $token_file !~ m/^\d+\.token\.\Q$token\E$/;
        unlink $token_dir . '/' . $token_file;
        return 1;
    }

    Cpanel::Debug::log_info("Failed to verify token $token");
    return;
}

sub expire_tokens {
    if ( opendir my $token_DH, $token_dir ) {
        my $mtime_to_beat = time - 10800;
        my @tokens        = readdir $token_DH;
        closedir $token_DH;
        foreach my $token_file (@tokens) {
            if ( $token_file =~ m/^(\d+)\.token\.\S+$/ ) {
                if ( $1 < $mtime_to_beat ) {
                    unlink $token_dir . '/' . $token_file;
                }
            }
        }

    }
    else {
        Cpanel::Debug::log_warn("Failed to read $token_dir: $!");
    }
    return 1;
}

1;
