package Cpanel::cPCPAN::Utils;

# cpanel - Cpanel/cPCPAN/Utils.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub _cpanelservers {
    my @URLS;

    require Cpanel::Config::Sources;
    my $CPSRC = Cpanel::Config::Sources::loadcpsources();

    my @IPS = _getAddressList( $CPSRC->{'HTTPUPDATE'} );
    foreach my $ip (@IPS) {
        push( @URLS, 'http://' . $ip . '/pub/CPAN' );
    }
    return wantarray ? @URLS : \@URLS;
}

sub _getAddressList {
    my $host = shift;

    require Socket;
    my @addresses = gethostbyname($host);
    my (@trueaddresses);
    foreach my $address ( @addresses[ 4 .. $#addresses ] ) {
        push( @trueaddresses, Socket::inet_ntoa($address) );
    }

    if ( $#trueaddresses == -1 ) {
        die "$host could not be resolved to an ip address, please check your /etc/resolv.conf";
    }

    return wantarray ? @trueaddresses : \@trueaddresses;
}

sub save_version_updates {
    my $self = shift;
    print "Saving modules.versions update\n";

    if ( open my $mv_fh, '>', $self->{'basedir'} . '/.cpcpan/UPDATE/modules.versions' ) {
        foreach my $mod ( sort keys %{ $self->{'new_modversions'} } ) {
            print {$mv_fh} $mod . '=' . $self->{'new_modversions'}{$mod} . "\n";
        }
        close $mv_fh;
    }
}

sub get_root_module_from_file {
    my $file = shift;

    my @PATH = split( /\/+/, $file );

    my $filename = pop @PATH;

    my @MODNAME = split( /-/, $filename );
    pop @MODNAME;

    return join( '::', @MODNAME );

}

1;
