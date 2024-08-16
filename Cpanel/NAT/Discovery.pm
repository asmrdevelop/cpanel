package Cpanel::NAT::Discovery;

# cpanel - Cpanel/NAT/Discovery.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Sources           ();
use Cpanel::Ips                       ();
use Cpanel::Logger                    ();
use Cpanel::HTTP::Tiny::FastSSLVerify ();

sub new {
    my ($class) = @_;

    my $logger = Cpanel::Logger->new() or die "failed to initialize logger";

    my $self = {
        cpnat_file => '/var/cpanel/cpnat',
        logger     => $logger,
        failures   => {},
        ip_map     => {},
    };

    bless $self, $class;

    return $self;
}

sub verify_route {
    my ( $self, $ip ) = @_;

    my $url = Cpanel::Config::Sources::get_source('MYIP');

    # Cpanel::HTTP::Client will try each MYIP server (there are usually at least 4)
    # before timing out.  We set the timeout to 2.5s which works as a connect timeout
    # and read_timeout to 10s for once we have an established connection since unrouteable
    # addresses will always reach the connect() timeout of 2.5s
    my $ua        = Cpanel::HTTP::Tiny::FastSSLVerify->new( 'connect_timeout' => 2.5, 'timeout' => 10, 'local_address' => $ip );
    my $response  = $ua->get($url);
    my $remote_ip = '';

    # Used to sort the IP list
    my $decimal_ip = _ip_to_32bit($ip);

    if ( $response->{success} ) {
        $remote_ip = $response->{content};
        chomp $remote_ip;
        $self->{ip_map}->{$decimal_ip} = $remote_ip;
        $self->logger->info("$ip => $remote_ip");
    }
    else {
        # houston, we have a problem

        $self->{ip_map}->{$decimal_ip} = '';

        my $error = $response->{status};
        chomp $error;

        if ( $error =~ m/^404\b/ ) {
            $self->logger->die( "Unable to map $ip - Cannot connect to $url : " . $response->{'reason'} );
        }

        $self->logger->warn("Unable to map $ip");
        $self->{failures}->{$ip} = {
            'error'     => $error,
            'interface' => $self->{'local_ip'}->{'if'}
        };
    }

    return $remote_ip;
}

sub discover {
    my ($self) = @_;
    my $system_ips = Cpanel::Ips::fetchifcfg();

    $self->logger->die("No system interfaces are configured with an IP.") if !@$system_ips;

    for my $if (@$system_ips) {
        my $local_ip = $if->{'ip'};
        $self->verify_route($local_ip);
    }

    if ( !grep /\S+/, values %{ $self->{ip_map} } ) {
        $self->logger->die("No publicly routable addresses found");
    }

    # Die if all IPs bound to interfaces are the same as remote IP (Not a NAT system)
    my $flag = 0;
    while ( my ( $ip, $remote ) = each %{ $self->{ip_map} } ) {
        next if $remote =~ m/^\s*$/;
        my $converted_ip = _convert_to_ip($ip);
        if ( $converted_ip ne $remote ) {
            $flag++;
            last;
        }
    }

    unless ($flag) {
        $self->logger->info("All publicly routeable addresses are the same as the local address. Not a NAT system.");
        if ( unlink $self->{'cpnat_file'} ) {
            $self->logger->info( "Removing " . $self->{'cpnat_file'} );
        }
        return;
    }

    $self->write_cpnat_file();

    return $self->{failures};
}

sub write_cpnat_file {
    my ( $self, $args ) = @_;
    $args->{append} ||= 0;

    my $cpnat_file = $self->{cpnat_file};

    my $fh;
    if ( $args->{append} ) {
        open $fh, '>>', $cpnat_file or $self->logger->die("Cannot write to $cpnat_file - $!");
    }
    else {
        open $fh, '>', $cpnat_file or $self->logger->die("Cannot write to $cpnat_file - $!");
    }

    foreach my $ip ( sort keys %{ $self->{ip_map} } ) {
        my $converted_ip = _convert_to_ip($ip);
        print {$fh} "$converted_ip " . $self->{ip_map}->{$ip} . "\n";
    }
    close $fh;

    return;
}

# Convert 32bit to IPV4
sub _convert_to_ip {
    return join '.', unpack( 'C*', pack( 'N', shift ) );
}

sub _ip_to_32bit {
    return unpack( 'N', pack 'C*', split /\./, shift );
}

sub logger {
    return shift->{logger};
}

1;
