package Cpanel::CloudLinux;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

use Cpanel::Autodie::IO      ();
use Cpanel::Autodie::Open    ();
use Cpanel::Binaries         ();
use Cpanel::Config::Sources  ();
use Cpanel::CachedCommand    ();
use Cpanel::FileUtils::Write ();
use Cpanel::JSON             ();
use Cpanel::Logger           ();
use Cpanel::OS               ();
use Cpanel::OSSys::Env       ();
use Cpanel::Pkgr             ();
use Cpanel::SafeRun::Object  ();

use Cpanel::Imports;

sub installed {
    return Cpanel::OS::is_cloudlinux();
}

my $spacewalk = '/usr/sbin/spacewalk-channel';

# CloudLinux is configured and installed (kernel module check not included)
sub enabled {
    if ( has_channel() && installed() ) {
        return 1;
    }
    return 0;
}

sub nocloudlinux {
    return -e '/var/cpanel/nocloudlinux' || -e '/var/cpanel/disabled/cloudlinux';
}

# Licensed through cPanel
sub licensed {
    my $cpanel_bin   = '/usr/local/cpanel/cpanel';
    my $cpanel_flags = Cpanel::CachedCommand::cachedcommand_multifile( ['/usr/local/cpanel/cpanel.lisc'], $cpanel_bin, '-F' );
    chomp $cpanel_flags;
    if ($cpanel_flags) {
        my @flags = split( /,/, $cpanel_flags );
        if ( grep { $_ eq 'cloudlinux' } @flags ) {
            return 1;
        }
    }
    return 0;
}

# RHN CloudLinux channel configured
sub has_channel {
    if ( !-x $spacewalk ) {
        return 0;
    }

    my $rhn_channel_list = Cpanel::CachedCommand::noncachedcommand( $spacewalk, '--list' );
    if ( $rhn_channel_list =~ m/\bcloudlinux\b/m ) {
        return 1;
    }
    return 0;
}

# Running kernel has lve module loaded
sub kernel_support {
    if ( open my $proc_modules_fh, '<', '/proc/modules' ) {
        while ( my $line = readline $proc_modules_fh ) {
            if ( $line =~ m/^lve\s/ ) {
                close $proc_modules_fh;
                return 1;
            }
        }
        close $proc_modules_fh;
    }
    return 0;
}

sub supported_envtype {
    my $envtype = Cpanel::OSSys::Env::get_envtype();

    # We can support any envtype where the virtualization isn't handled by the kernel itself
    if (   $envtype eq 'standard'
        || $envtype eq 'hyper-v'
        || $envtype eq 'kvm'
        || $envtype eq 'smartos'
        || $envtype eq 'parallels'
        || $envtype eq 'vmware'
        || $envtype eq 'virtualbox'
        || $envtype =~ /^xen/ ) {
        return 1;
    }
    return 0;

}

# For testing purposes
sub set_spacewalk_bin {
    return ( $spacewalk = $_[0] );
}

sub get_promotional_data {
    my $cl_data = {};
    $cl_data->{'cl_is_installed'} = Cpanel::OS::is_cloudlinux();

    $cl_data->{'cl_is_supported'} = 1;
    if ( !$cl_data->{'cl_is_installed'} ) {
        $cl_data->{'cl_is_supported'} = Cpanel::CloudLinux::supported_envtype() && Cpanel::OS::supports_or_can_become_cloudlinux();
    }

    $cl_data->{'purchase_cl_data'} = Cpanel::CloudLinux::get_purchase_cloudlinux_data();
    return $cl_data;
}

sub get_purchase_cloudlinux_data {    # un-ea3'd version of Cpanel::Easy::Utils::CloudLinux::get_purchase_cloudlinux_data()
    my $data;

    my $prefs = { disable_cloudlinux_infrastructure => 0 };    # TODO: where to get this value? for now use ea3 name and set to false

    # Short-circuit any checking if the disable preference is checked
    if ( defined $prefs->{'disable_cloudlinux_infrastructure'} && $prefs->{'disable_cloudlinux_infrastructure'} == 1 ) {
        $data = {
            'is_url'          => 0,
            'server_timeout'  => 0,
            'disable_upgrade' => 1,
        };
    }

    if ($data) {

        # See ZC-1715 for why this is necessary, (sadpanda)
        for my $key ( keys %{$data} ) {
            if ( $data->{$key} =~ m/\A[0-9]+\z/ ) {
                $data->{$key} = int( $data->{$key} );
            }
        }
    }
    else {
        require HTTP::Tiny;    # do not use Cpanel::HTTP::Client, see ZC-1703 for specifics
                               # in ea3 it was /var/cpanel/easy/apache/cache/manage2_cloudlinux.yaml but we do not want to be ea3 specific here

        my $url = sprintf( '%s/cloudlinux.cgi', Cpanel::Config::Sources::get_source('MANAGE2_URL') );

        my $raw_resp = HTTP::Tiny->new( 'timeout' => 10 )->get($url);
        my $json_resp;

        if ( $raw_resp->{'success'} ) {
            eval { $json_resp = Cpanel::JSON::Load( $raw_resp->{'content'} ) };

            if ($@) {
                $json_resp = undef;
                logger->warn( "Invalid server response from " . Cpanel::Config::Sources::get_source('MANAGE2_URL') );
            }
        }

        $data = {
            'is_url'          => 0,
            'server_timeout'  => 0,
            'disable_upgrade' => 0
        };

        if ($json_resp) {
            if ( $json_resp->{'disabled'} ) {
                $data->{'disable_upgrade'} = 1;
            }
            else {
                if ( $json_resp->{'url'} ) {
                    $data->{'is_url'} = 1;

                    # This is skiping a bug from Manage2. See OPRAH-6934 for more details.
                    if ( $json_resp->{'url'} eq 'https://store.cpanel.net/view/cloudlinux' ) {
                        $data->{'url'} = '';
                    }
                    else {
                        $data->{'url'} = $json_resp->{'url'};
                    }
                }
                else {
                    $data->{'email'} = $json_resp->{'email'};
                }
            }
        }
        else {
            $data->{'server_timeout'} = 1;
        }

    }

    return $data;
}

# It took 8 minutes to convert a box to CL under ideal circumstances, give an hour to be safe
our $cloudlinux_install_timeout = 3600;
our $log_path                   = '/var/cpanel/logs/cloudlinux-install.log';

sub install_cloudlinux {
    my $cldeploy_script = Cpanel::CloudLinux::get_cldeploy();

    my $bash_bin = Cpanel::Binaries::path('bash');
    die locale()->maketext('The system could not find the “[asis,bash]” binary in the expected location while preparing to install [asis,CloudLinux].') if !-x $bash_bin;

    Cpanel::Autodie::Open::open( my $log_fh, '>', $log_path );

    # Make sure nothing else is trying to do pkgr install activity right now.
    my $logger = Cpanel::Logger->new;
    $logger->set_fh($log_fh);
    my $lock = Cpanel::Pkgr::lock_for_external_install($logger);

    my $run = Cpanel::SafeRun::Object->new(
        program => $bash_bin,
        args    => [
            $cldeploy_script,
            '-i',                  # The CloudLinux licenses issued by the cPanel store are only IP based, not key-based
            '--noninteractive',    # Make sure the script does not prompt for STDIN
        ],
        after_fork => sub {
            $0 = 'Install CloudLinux';
        },
        stdout  => $log_fh,
        stderr  => $log_fh,
        timeout => $cloudlinux_install_timeout,
    );

    Cpanel::Autodie::IO::close($log_fh);

    if ( $run->CHILD_ERROR() ) {
        my $tail_bin = Cpanel::Binaries::path('tail');
        my $tail_obj = Cpanel::SafeRun::Object->new(
            program => $tail_bin,
            args    => [
                '-n20',
                $log_path,
            ],
        );
        die locale()->maketext( 'The log file contained the following information: [_1]', $tail_obj->stdout );
    }

    return;
}

our $install_url   = 'https://repo.cloudlinux.com/cloudlinux/sources/cln/cldeploy';
our $cldeploy_path = '/usr/local/cpanel/tmp/cldeploy';

sub get_cldeploy {
    require Cpanel::HTTP::Client;
    my $response = eval {
        my $http = Cpanel::HTTP::Client->new()->die_on_http_error();
        $http->get($install_url);
    };
    if ( my $exception = $@ ) {
        die locale()->maketext( 'The system could not fetch the installation script: [_1]', $exception );
    }

    Cpanel::FileUtils::Write::overwrite( $cldeploy_path, $response->{content} );

    return $cldeploy_path;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::CloudLinux - CloudLinux related utilities

=head1 INTERFACE

=head2 Functions

=head3 get_purchase_cloudlinux_data()

This function performs a web request to manage2 API to get purchase information for CloudLinux from the hostname.

Takes no arguments, returns a hash reference of the API call’s JSON (is_url, server_timeout, url, email).

=head3 install_cloudlinux()

This function is a wrapper for the cldeploy script that is used to convert an OS
to CloudLinux.  When called, it will attempt to convert the OS to CloudLinux.

Take no arguments, returns undef.

=head3 get_cldeploy()

The function downloads the latest version of the cldeploy script to the server.

Takes no arguments, returns the path to the cldeploy script.

=head3 not all functions are currently documented :(
