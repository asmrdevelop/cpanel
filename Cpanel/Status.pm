package Cpanel::Status;

# cpanel - Cpanel/Status.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 NAME

C<Cpanel::Status>

=head1 DESCRIPTION

Utilities for getting various system level information:

 * number of cpus
 * monitored services and their current status.
 * disk usage
 * software versions where available

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Carp ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Math     ();
use Cpanel::SafeFile ();
use Cpanel::Imports;

use constant CHKSERVD_CONFIG_PATH   => '/etc/chkserv.d/chkservd.conf';
use constant CHKSERVD_RUN_DIRECTORY => '/var/run/chkservd';

our $VERSION = '1.2';

sub memory_totals {
    if ( open( my $meminfo_fh, '<', '/proc/meminfo' ) ) {
        my %meminfo;
        while (<$meminfo_fh>) {
            if (m/^([a-zA-Z]+):\s*([0-9]+)/) { $meminfo{$1} = $2; }
        }

        my $memused  = $meminfo{MemTotal} - $meminfo{MemFree} - $meminfo{Buffers} - $meminfo{Cached};
        my $swapused = $meminfo{SwapTotal} - $meminfo{SwapFree};

        return ( $memused, $meminfo{MemTotal}, $swapused, $meminfo{SwapTotal} );
    }
    else { return -1; }
}

sub memory_percents {
    my ( $memused, $memtotal, $swapused, $swaptotal ) = memory_totals();
    if ( $memused == -1 ) { return ( -1, -1 ) }

    my $memper = $memused / $memtotal;
    $memper = Cpanel::Math::floatto( 100 * $memper, 2 );

    my $swapper = ( $swaptotal == 0 ) ? 0 : $swapused / $swaptotal;
    $swapper = Cpanel::Math::floatto( 100 * $swapper, 2 );

    return ( $memper, $swapper );
}

=head2 get_monitored_services()

For each service enabled in C<CHKSRVD_CONFIG_PATH>, get the monitored status for each service
in C<CHKSRVD_RUN_DIRECTORY/[service]>.

=head3 RETURNS

hashref of key value pairs for each service where each hash has the following properties:

=over

=item status - boolean

Status of the monitored service.

=item error - string

Only present if there is a problem checking the status file.

=back

=cut

sub get_monitored_services {

    my %services;

    if ( my $conf_lock = Cpanel::SafeFile::safeopen_skip_dotlock_if_not_root( my $chkservd_config_fh, '<', CHKSERVD_CONFIG_PATH ) ) {
        while (<$chkservd_config_fh>) {
            chomp;
            my ( $service, $status ) = split( /\s*:\s*/, $_ );
            next if ( !defined($service) || $service eq '' );
            next if ( !defined($status)  || $status eq '' );
            next if ( int $status != 1 );
            next if ( _exists( '/etc/' . $service . 'disable' ) );

            my $status_file = CHKSERVD_RUN_DIRECTORY . "/${service}";
            if ( my $status_lock = Cpanel::SafeFile::safeopen_skip_dotlock_if_not_root( my $status_fh, '<', $status_file ) ) {
                chomp( my $contents = <$status_fh> );
                $services{$service} = { status => $contents eq '+' ? 1 : 0 };
                Cpanel::SafeFile::safeclose( $status_fh, $status_lock );
            }
            else {
                $services{$service} = { error => locale()->maketext( 'The system could not retrieve the service status for “[_1]”.', $service ) };
            }
        }
        Cpanel::SafeFile::safeclose( $chkservd_config_fh, $conf_lock );
    }

    return \%services;

}

# for mocking
sub _exists {
    return -e $_[0];
}

1;
