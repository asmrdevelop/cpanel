package Cpanel::SSH::KeyBackend;

# cpanel - Cpanel/SSH/KeyBackend.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Binaries  ();
use Cpanel::Exception ();
use Cpanel::Expect    ();
use Cpanel::Logger    ();

my $logger = Cpanel::Logger->new();

sub validate_key_passphrase {
    my ( $path, $passphrase ) = @_;

    if ( !length $path ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide the path to the SSH private key.' );
    }
    elsif ( !-e $path ) {
        die Cpanel::Exception::create( 'IO::FileNotFound', 'The system failed to locate the file “[_1]”.', [$path] );
    }
    elsif ( !-f $path ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The filesystem node “[_1]” is not a regular file.', [$path] );
    }

    my $keygen_bin = Cpanel::Binaries::path('ssh-keygen');

    my $expect = Cpanel::Expect->spawn( $keygen_bin, '-y', '-f', $path );

    if ( !$expect ) {
        die Cpanel::Exception->create( 'The system failed to execute “[_1]” because of an error: [_2]', [ $keygen_bin, $! ] );
    }

    $expect->log_stdout(0);
    $expect->expect(
        5,
        [
            ':',
            sub {
                $expect->do($passphrase);
            }
        ]
    );
    $expect->soft_close();
    return $? ? 0 : 1;
}

1;
