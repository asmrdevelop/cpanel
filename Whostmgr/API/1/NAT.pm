package Whostmgr::API::1::NAT;

# cpanel - Whostmgr/API/1/NAT.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant NEEDS_ROLE => {
    nat_checkip       => undef,
    nat_set_public_ip => undef,
    natd              => undef,
};

our $natd;

sub nat_checkip {
    my ( $args, $metadata ) = @_;

    require Cpanel::NAT::Discovery;
    $natd ||= Cpanel::NAT::Discovery->new();
    my $ip;
    eval { $ip = $natd->verify_route( $args->{'ip'} ) };
    my $errors = $@;
    if ( !$errors ) {
        nat_set_public_ip( { 'local_ip' => $args->{'ip'}, 'public_ip' => $ip }, $metadata );
        return { checked_ip => $ip };
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $errors;
        return { error => $errors };
    }
}

sub nat_set_public_ip {
    my ( $args, $metadata ) = @_;

    my $local_ip  = $args->{'local_ip'};
    my $public_ip = $args->{'public_ip'};

    require Cpanel::NAT::Discovery;
    $natd ||= Cpanel::NAT::Discovery->new();
    my $cpnat_file = $natd->{'cpnat_file'};

    my $buffer;
    if ( open( my $fh, '<', $cpnat_file ) ) {
        while ( my $line = <$fh> ) {

            if ( $line =~ /^$local_ip\s/ ) {
                $buffer .= "$local_ip $public_ip" . "\n";
            }
            else {
                $buffer .= $line;
            }
        }
    }

    if ( $buffer && open( my $fh, '>', $cpnat_file ) ) {
        print {$fh} $buffer;

        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Failed to write file';
    }

    return;
}

1;
