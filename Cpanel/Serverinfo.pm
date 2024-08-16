package Cpanel::Serverinfo;

# cpanel - Cpanel/Serverinfo.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.9';

use Cpanel::ConfigFiles::Apache           ();
use Cpanel::Status                        ();
use Cpanel                                ();
use Cpanel::DbUtils                       ();
use Cpanel::GlobalCache                   ();
use Cpanel::Htaccess                      ();
use Cpanel::ConfigFiles::Apache::modules  ();
use Cpanel::Config::LoadCpConf            ();
use Cpanel::LoadModule                    ();
use Cpanel::Pkgr                          ();
use Cpanel::SafeRun::Object               ();
use Cpanel::Server::Type::Role::WebServer ();

=pod

=head1 NAME

C<Cpanel::Serverinfo>

=head1 DESCRIPTION

Various helper methods to get information about the server.

=head1 FUNCTIONS

=cut

sub _machine {
    return $Cpanel::machine;
}

sub _kernelver {
    return $Cpanel::release;
}

sub _sendmailpath {
    return '/usr/sbin/sendmail';
}

sub _mysqlversion {
    my $mysqlbin = Cpanel::DbUtils::find_mysqld();
    if ($mysqlbin) {
        my $mysqlv = Cpanel::GlobalCache::cachedcommand( 'cpanel', $mysqlbin, '--version' );
        $mysqlv =~ /Ver\s(\S+)\s/;
        return $1;
    }
    return 'unknown';
}

sub _apacheversion {
    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();
    return ( Cpanel::ConfigFiles::Apache::modules::apache_long_version || 'unknown' );
}

sub _exim_version {
    return Cpanel::Pkgr::get_package_version('cpanel-exim');
}

# for mocking
sub _exists {
    return -e $_[0];
}

sub _load_average {

    my $load = 'unknown';
    if ( _exists('/proc/loadavg') ) {
        if ( open my $loadavg_fh, '<', '/proc/loadavg' ) {
            while (<$loadavg_fh>) {
                $load = ( split( /\s/, $_, 2 ) )[0];
                last;
            }
            close $loadavg_fh;
        }
    }

    if ( $load eq 'unknown' ) {
        my $command = Cpanel::SafeRun::Object->new( 'program' => 'uptime', 'timeout' => 10 );

        if ( !$command->CHILD_ERROR() ) {
            my $uptime = $command->stdout();
            if ( $uptime =~ /(\d+\.\d+)/ ) {
                $load = $1;
            }
        }
    }

    return $load;

}

sub cpu_information {

    my $cpunum;
    my $cpuname;

    if ( _exists('/proc/cpuinfo') ) {
        if ( open( my $CPUINFO, '<', '/proc/cpuinfo' ) ) {
            while (<$CPUINFO>) {
                if (/^processor\s*:\s*(.*)/) {
                    $cpunum = $1;
                    $cpunum++;
                }
            }
            close($CPUINFO);
        }
    }
    else {

        my $name_command = Cpanel::SafeRun::Object->new( 'program' => 'sysctl', 'args' => ['hw.model'], 'timeout' => 10 );
        my $num_command  = Cpanel::SafeRun::Object->new( 'program' => 'sysctl', 'args' => ['hw.ncpu'],  'timeout' => 10 );

        $cpuname = ( split( /:/, $name_command->stdout() ) )[1] unless $name_command->CHILD_ERROR();
        $cpunum  = ( split( /:/, $num_command->stdout() ) )[1]  unless $num_command->CHILD_ERROR();
        $cpunum  =~ s/\s|\n//g;
        $cpuname =~ s/\n//g;
        $cpuname =~ s/^\s*|\s*$//g;
    }

    if ( $cpunum eq '' ) {
        my $ncpus = Cpanel::SafeRun::Object->new( 'program' => '/usr/local/cpanel/bin/ncpus', 'timeout' => 10 );
        $cpunum = $ncpus->stdout() unless $ncpus->CHILD_ERROR();
        $cpunum =~ s/\n//g;
    }

    my %CCONF = Cpanel::Config::LoadCpConf::loadcpconf();

    my $cpumax = $cpunum;
    if ( $CCONF{'loadthreshold'} ) { $cpumax = $CCONF{'loadthreshold'}; }

    return ( $cpunum, $cpumax );

}

sub disk_free {

    Cpanel::LoadModule::loadmodule("DiskLib");
    my $diskfree_ref = Cpanel::DiskLib::get_disk_used_percentage_with_dupedevs();

    my @disks;
    foreach my $device ( sort { length $a->{mount} <=> length $b->{mount} || $a->{mount} cmp $b->{mount} } @{$diskfree_ref} ) {

        push @disks, {
            filesystem => $device->{filesystem},
            mount      => $device->{mount},
            disk_used  => $device->{percentage}
        };
    }

    return @disks;

}

=head2 get_status()

Gets the status information for the server. This includes the status of
monitored services as well as:

 * server load
 * cpu count
 * memory used
 * swap used
 * disk usage

=head3 RETURNS

Array of hashes with the following format:

=over

=item name - string

Name of the service or stat

=item type - string

One of: service, metric or device

=item status - string | number

When the status if for a service, indicates weather or not the service is monitored

When the status if for disk, memory or similar resource, the value will be one of the following:

=over

=item -1 - Usage is > 90%

=item 0 - Usage is > 80%

=item 1 - Usage is < 80%

=back

=item value - string | number

When a string and the status if for a service, the value is one of the following:

=over

=item up - Service is up

=item down - Service is down

=item unknown - Service information is not accessible

=back

Other status are commonly numbers measuring the percent used or similar metrics.

=item error - string

Only present when the service information can not be accessed.

=back

=cut

sub get_status {

    Cpanel::LoadModule::loadmodule('Status');
    my $monitored_services = Cpanel::Status::get_monitored_services();
    my @status             = ();

    #try and get version information
    # todo: CASE DUCK-196
    # api1 attempted to get versions for bind and proftpd
    # but not pureftpd or powerdns, so it was always empty
    # if this is critical we have to find a way to handle these

    foreach my $service ( sort keys %{$monitored_services} ) {
        my $result      = $monitored_services->{$service};
        my %information = (
            'type'   => 'service',
            'name'   => $service,
            'status' => $result->{error} ? undef     : $result->{status},
            'value'  => $result->{error} ? 'unknown' : $result->{status} == 0 ? 'down' : 'up',
            ( defined $result->{error} ? ( 'error' => $result->{error} ) : () ),
        );

        if ( $service eq 'httpd' ) {
            $information{'version'} = _apacheversion();
        }
        elsif ( $service eq 'mysql' ) {
            $information{'version'} = _mysqlversion();
        }
        elsif ( $service eq 'exim' ) {
            $information{'version'} = _exim_version();
        }

        push @status, \%information;

    }

    my $load_average = _load_average();
    my ( $cpu_count, $cpu_max ) = cpu_information();

    push @status, {
        'type'   => 'metric',
        'name'   => "Server Load",
        'value'  => $load_average,
        'status' => $load_average > $cpu_max ? 0 : 1
    };

    push @status, {
        'type'   => 'metric',
        'name'   => "CPU Count",
        'value'  => $cpu_count,
        'status' => 1
    };

    my ( $memper, $swapper ) = Cpanel::Status::memory_percents();

    my $mem_message  = ( $memper < 0 )  ? 'Unknown (Could not read /proc/meminfo)' : "$memper%";
    my $swap_message = ( $swapper < 0 ) ? 'Unknown (Could not read /proc/meminfo)' : "$swapper%";

    my $mem_status  = 1;
    my $swap_status = 1;
    $mem_status  = 0  if $memper > 80;
    $mem_status  = -1 if $memper > 90;
    $swap_status = 0  if $swapper > 80;
    $swap_status = -1 if $swapper > 90;

    push @status, {
        'type'   => 'device',
        'name'   => 'Memory Used',
        'value'  => $mem_message,
        'status' => $mem_status
    };

    push @status, {
        'type'   => 'device',
        'name'   => 'Swap',
        'value'  => $swap_message,
        'status' => $swap_status
    };

    foreach my $disk ( disk_free() ) {

        my $disk_status = 1;
        $disk_status = -1 if $disk->{disk_used} > 90;
        $disk_status = 0  if $disk->{disk_used} > 80;

        push @status, {
            'type'   => 'device',
            'name'   => 'Disk ' . $disk->{filesystem} . ' (' . $disk->{mount} . ')',
            'value'  => $disk->{disk_used} . '%',
            'status' => $disk_status
        };
    }

    return \@status;

}

1;
