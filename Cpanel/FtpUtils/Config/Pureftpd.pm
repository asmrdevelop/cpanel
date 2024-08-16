package Cpanel::FtpUtils::Config::Pureftpd;

# cpanel - Cpanel/FtpUtils/Config/Pureftpd.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::FtpUtils::Config );

no warnings 'redefine';

use Cpanel::Autodie ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

use Cpanel::LoadModule           ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::Debug                ();
use Cpanel::CachedCommand        ();
use Cpanel::FindBin              ();
use Cpanel::OS                   ();
use Cpanel::SafeDir::MK          ();
use Cpanel::NAT                  ();
use Cpanel::DIp::MainIP          ();
use Cpanel::SSL::Defaults        ();

#NB: Pure-FTPd doesn’t really have “configuration files” per se; rather,
#all arguments are passed in via command-line. The “pure-config.pl” script
#wraps Pure-FTPd with a parser that converts config file parameters into
#command-line parameters for the Pure-FTPd daemon. This is that file:
our $_CONF_FILE = '/etc/pure-ftpd.conf';

my %defaults;

sub _init_defaults {    # cannot run at BEGIN time, run it on demand once when required
    return if defined $defaults{'TLS'};

    %defaults = (
        'AnonymousCantUpload'        => 'no',
        'BrokenClientsCompatibility' => 'no',
        'MaxLoad'                    => 4,
        'MaxIdleTime'                => 15,
        'MaxClientsNumber'           => 50,
        'MaxClientsPerIP'            => 8,
        'TLS'                        => 1,
        'Bind'                       => '21',
        'TLSCipherSuite'             => Cpanel::SSL::Defaults::default_cipher_list(),
        'ExtAuth'                    => '/var/run/ftpd.sock',
        'PassivePortRange'           => '49152 65534',

        # always need to disable daemon on C7 for systemd.service script
        'Daemonize' => Cpanel::OS::is_systemd() ? 'No' : 'Yes',
        'AltLog'    => 'xferlog:' . apache_paths_facade->dir_domlogs() . '/ftpxferlog',
    );

    # If pure-ftpd is behind NAT, it will advertise its internal IP address
    # by default, and passive mode will fail to work. In this case, we must
    # instruct it to advertise its public IP address.
    my $main_ip   = Cpanel::DIp::MainIP::getmainip();
    my $public_ip = Cpanel::NAT::get_public_ip($main_ip);

    if ( $main_ip ne $public_ip ) {
        $defaults{'ForcePassiveIP'} = $public_ip;
    }

    return;
}

sub new {
    my $class = shift;
    my $self  = $class->SUPER::_init();
    $self->find_conf_file();
    $self->{'display_name'}       = 'Pure-FTPd';
    $self->{'type'}               = 'pure-ftpd';
    $self->{'datastore_name'}     = 'pureftpd';
    $self->{'pureftpd_version'}   = '';
    $self->{'pureftpd_bin_mtime'} = 0;
    return $self;
}

sub find_conf_file {
    my $self = shift;
    return $self->{'conf_file'} if defined $self->{'conf_file'};

    # TODO Cleanup ugly code from ftpup
    my $conf = $_CONF_FILE;
    if ( !Cpanel::Autodie::exists($conf) ) {
        if ( Cpanel::Autodie::exists("${conf}.sample") ) {
            system( "cp", "-f", "${conf}.sample", $conf ) and die;
        }
    }

    $self->{'conf_file'} = $conf;
    return $conf;
}

sub read_settings_from_conf_file {
    my $self    = shift;
    my $conf_hr = {};

    my $conf_file = $self->find_conf_file();
    if ( !length $conf_file || !-e $conf_file || -z _ ) {
        my $display_name = $self->{display_name};
        Cpanel::Debug::log_warn("The $display_name configuration file '$conf_file' is missing or empty.");
        return $conf_hr;
    }

    foreach my $line ( split( m{\n}, $self->_slurp_config() ) ) {
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*#/;
        if ( $line =~ /^\s*(\S+)\s*(\S.*)/ ) {
            my $key = $1;
            my $val = $2;
            chomp $val;
            $conf_hr->{$key} = $val;
        }
    }

    $conf_hr->{'RootPassLogins'} = 'no';

    $conf_hr->{'HasTLS3Support'} = $self->min_version('1.0.22');
    return $conf_hr;
}

sub get_port {
    my ($self) = @_;

    # internal cache
    return $self->{port} if defined $self->{port};

    my $conf = $self->read_settings_from_conf_file();
    $self->check_for_unset_defaults($conf);

    my $bind = $conf->{'Bind'};

    return unless defined $bind;
    $bind =~ s/#.*$//;
    $bind =~ s/\s*$//;

    my ( $listen, $port ) = split( /\s*,\s*/, $bind );

    $port = $listen if !$port;

    $self->{port} = int($port);

    return $self->{port};
}

sub find_executable {
    my $self = shift;
    return $self->{'exe'} ||= Cpanel::FindBin::findbin(qw(pure-ftpd /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin));
}

sub get_version {
    my $self = shift;
    my $exe  = $self->find_executable();
    return unless defined $exe && -x $exe;
    my $exe_mtime = ( stat(_) )[9] || 0;
    return $self->{'pureftpd_version'} if ( $exe_mtime == $self->{'pureftpd_bin_mtime'} && $self->{'pureftpd_version'} );

    my $pureftpd_version = Cpanel::CachedCommand::cachedcommand( $exe, '--help' );
    if ( $pureftpd_version && $pureftpd_version =~ /^\s*pure-ftpd\s+v(\S+)/im ) {
        $self->{'pureftpd_version'}   = $1;
        $self->{'pureftpd_bin_mtime'} = $exe_mtime;
        return $self->{'pureftpd_version'};
    }
    else {
        return;
    }
}

sub check_for_unset_defaults {
    my $self    = shift;
    my $conf_hr = shift;

    _init_defaults();

    # Set defaults for configurable values we don't force elsewhere
    foreach my $key ( keys %defaults ) {
        if ( !exists $conf_hr->{$key} ) {
            $conf_hr->{$key} = $defaults{$key};
        }
    }
    $conf_hr->{'ExtAuth'}        = $defaults{'ExtAuth'};
    $conf_hr->{'AltLog'}         = $defaults{'AltLog'};
    $conf_hr->{'NoAnonymous'}    = -e '/var/cpanel/noanonftp' ? 'yes' : 'no';
    $conf_hr->{'RootPassLogins'} = defined $conf_hr->{'RootPassLogins'} ? $conf_hr->{'RootPassLogins'} : -e '/var/cpanel/conf/pureftpd/root_password_disabled' ? 'no' : 'yes';

    return $conf_hr;
}

sub update_config {
    my $self        = shift;
    my $settings_hr = shift;

    # Clone the hashref so that we can safely delete keys
    my $settings_hr_copy = {};
    %{$settings_hr_copy} = %{$settings_hr};

    $self->_validate_settings($settings_hr_copy);

    my $conf_file = $self->find_conf_file();

    Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::Raw');
    my $trans = Cpanel::Transaction::File::Raw->new( 'path' => $conf_file, perms => 0600 );

    my %already_seen;
    my $new_conf = '';
    foreach my $line ( split( m{^}, ${ $trans->get_data() } ) ) {
        if ( $line =~ /^\s*#?\s*(\S+)\s+(\S.*)/ ) {

            # This will match all directives and comments.
            my $key = $1;
            my $val = $2;
            if ( defined( $settings_hr_copy->{$key} ) ) {
                $line = $key . ' ' . $settings_hr_copy->{$key} . "\n";
                delete $settings_hr_copy->{$key};
                $already_seen{$key} = 1;
            }
            elsif ( exists( $settings_hr_copy->{$key} ) ) {
                $line = '# ' . $line if $line !~ /^\s*#/;
                delete $settings_hr_copy->{$key};
                $already_seen{$key} = 1;
            }
            elsif ( $already_seen{$key} && $line !~ /^\s*#/ ) {
                $line = '# ' . $line;
            }
        }
        $new_conf .= $line;
    }
    foreach my $new_setting ( keys %{$settings_hr_copy} ) {
        next
          if $new_setting eq 'RootPassLogins';
        $new_conf .= "\n";
        $new_conf .= $new_setting . ' ' . $settings_hr_copy->{$new_setting} . "\n";
    }

    $trans->set_data( \$new_conf );
    $trans->save_and_close_or_die();

    if ( $settings_hr->{'NoAnonymous'} eq 'no' ) {
        unlink '/var/cpanel/noanonftp' if ( -e '/var/cpanel/noanonftp' );
    }
    else {
        Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/noanonftp') unless ( -e '/var/cpanel/noanonftp' );
    }

    if ( $settings_hr->{'RootPassLogins'} eq 'no' ) {
        unless ( -d '/var/cpanel/conf/pureftpd' ) {
            Cpanel::SafeDir::MK::safemkdir( '/var/cpanel/conf',          '0700' );
            Cpanel::SafeDir::MK::safemkdir( '/var/cpanel/conf/pureftpd', '0700' );
        }
        Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/conf/pureftpd/root_password_disabled');
    }
    else {
        unlink '/var/cpanel/conf/pureftpd/root_password_disabled' if ( -e '/var/cpanel/conf/pureftpd/root_password_disabled' );
    }

    # Chkservd can't authenticate when TLS is required
    if ( $settings_hr->{'TLS'} eq '2' || $settings_hr->{'TLS'} eq '3' ) {
        Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/ftpd_service_auth_check_disabled') unless ( -e '/var/cpanel/ftpd_service_auth_check_disabled' );
    }
    else {
        unlink '/var/cpanel/ftpd_service_auth_check_disabled' if ( -e '/var/cpanel/ftpd_service_auth_check_disabled' );
    }

    return 1;
}

sub set_anon {
    my $self          = shift;
    my $anonymous_ftp = $self->_parse_anon_arg($@);
    my $conf_hr       = $self->load_datastore();
    $conf_hr->{'NoAnonymous'} = $anonymous_ftp ? 'no' : 'yes';

    $self->save_datastore($conf_hr);
    $self->update_config($conf_hr);
}

sub save_datastore {
    my $self    = shift;
    my $conf_hr = shift;
    $self->_validate_settings($conf_hr);
    return $self->SUPER::save_datastore($conf_hr);
}

sub _validate_settings {    ## no critic qw(Subroutines::ProhibitExcessComplexity) - Refactoring this function is beyond the scope of a bugfix
    my $self        = shift;
    my $settings_hr = shift;

    _init_defaults();

    delete $settings_hr->{'HasTLS3Support'};

    foreach my $key ( keys %{$settings_hr} ) {
        my $val   = $settings_hr->{$key};
        my $valid = 1;
        if ( $key eq 'MaxLoad' || $key eq 'MaxClientsNumber' || $key eq 'MaxClientsPerIP' ) {

            # Must be integer greater than 0
            $valid = 0 if ( !defined $val || $val !~ /^[1-9][0-9]*$/ );
        }
        elsif ( $key eq 'MaxIdleTime' ) {

            # Any Integer
            $valid = 0 if ( !defined $val || $val !~ /^[0-9]+$/ );
        }
        elsif ( $key eq 'TLS' ) {
            $valid = 0 if ( !defined $val || $val !~ /^[0123]$/ );
            if ( !$self->min_version('1.0.22') && $val eq '3' ) {
                $settings_hr->{$key} = '2';
            }
        }
        elsif ( $key eq 'ExtAuth' || $key eq 'AltLog' ) {

            # Not configurable
            $valid = 0 if ( !defined $val || $val ne $defaults{$key} );
        }
        elsif ( $key eq 'BrokenClientsCompatibility' ) {

            # yes or no
            $valid = 0 if ( !defined $val || $val !~ /^(yes|no)$/ );
        }
        elsif ( $key eq 'Daemonize' ) {
            $valid = 0 if $val ne $defaults{$key};
        }
        elsif ( $key eq 'ForcePassiveIP' && defined($val) && Cpanel::NAT::is_nat() ) {
            my $public_ips = Cpanel::NAT::get_all_public_ips();

            if ( !defined $val || !grep { $_ eq $val } @$public_ips ) {
                $valid = 0;

                # In testing we found that this default value could be undef in the right circumstances, so pick one of the public ips
                $defaults{$key} = $public_ips->[0] if !length $defaults{$key} && length $public_ips->[0];
            }
        }

        if ( !$valid && length $defaults{$key} ) {
            Cpanel::Debug::log_warn("Invalid $key setting, switching to default of $defaults{$key}");
            $settings_hr->{$key} = $defaults{$key};
        }
    }
    return 1;
}

# For tests
sub _clear_defaults {
    %defaults = ();

    return;
}

1;
