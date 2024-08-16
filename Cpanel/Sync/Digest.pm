package Cpanel::Sync::Digest;

# cpanel - Cpanel/Sync/Digest.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::SafeRun::Simple ();

our %digest_algorithms = (
    'md5' => {
        module => 'Digest::MD5',
        ctx    => sub { return Digest::MD5->new() },
        cmd    => 'md5sum',
    },
    'sha512' => {
        module => 'Digest::SHA',
        ctx    => sub { return Digest::SHA->new(512) },
        cmd    => 'sha512sum',
    },
);

for my $algo ( keys %digest_algorithms ) {
    my $module_file = $digest_algorithms{$algo}->{'module'};
    $module_file =~ s/::/\//g;
    $module_file = $module_file . '.pm';

    if ( eval { require $module_file } ) {
        $digest_algorithms{$algo}->{'module_loaded'} = 1;
    }
}

sub digest {
    my ( $file, $opts ) = @_;
    return undef if ( !$file );

    my $algo = $opts->{'algo'} ||= 'md5';
    return undef if ( !exists( $digest_algorithms{$algo} ) );

    if ( $digest_algorithms{$algo}->{'module_loaded'} ) {
        my $ctx = $digest_algorithms{$algo}->{'ctx'}->();

        if ( open( my $ctx_fh, '<', $file ) ) {
            binmode $ctx_fh;
            $ctx->addfile($ctx_fh);
            close($ctx_fh);
            return $ctx->hexdigest();
        }
        else {
            return undef;
        }
    }
    else {
        my $cmd      = $digest_algorithms{$algo}->{'cmd'};
        my $out      = Cpanel::SafeRun::Simple::saferunnoerror( $cmd, $file );
        my ($digest) = $out =~ /^([a-f0-9]+)\s+/;
        return $digest;
    }
}

1;
