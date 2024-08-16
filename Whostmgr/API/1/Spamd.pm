package Whostmgr::API::1::Spamd;

# cpanel - Whostmgr/API/1/Spamd.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();
use Cpanel::SafeFile           ();
use Cpanel::Locale             ();
use Cpanel::Logger             ();
use Cpanel::SafeRun::Errors    ();
use Cpanel::Validate::IP       ();

use File::Spec ();

use constant NEEDS_ROLE => 'SpamFilter';

my $logger = Cpanel::Logger->new();
my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

sub save_spamd_config {
    my ( $formref, $metadata ) = @_;

    my $spamd_conf    = _load_current_config();
    my $spamd_options = _get_spamd_options();

    foreach my $option ( sort keys( %{$spamd_options} ) ) {
        my $optionformat = $spamd_options->{$option};
        if ( $formref->{$option} ) {
            if ( _is_valid_option( $formref->{$option}, $optionformat ) ) {
                if ( $option eq "pidfile" ) {

                    # CPANEL-35268: Things the pidfile value can't be:
                    # - a relative path
                    # - a directory-like path (i.e., trailing slash)
                    # - a path whose directory does not exist
                    # - an existing directory
                    # - an existing file with non-digit contents
                    my $pidfile = $formref->{$option};
                    if ( !File::Spec->file_name_is_absolute($pidfile) ) {
                        $metadata->{'result'} = 0;
                        $metadata->{'reason'} = _locale()->maketext('You must enter an absolute path.');
                        return;
                    }

                    if ( $pidfile =~ m{(.*/)[^/]+$} && !-d $pidfile ) {
                        if ( !-d $1 ) {
                            $metadata->{'result'} = 0;
                            $metadata->{'reason'} = _locale()->maketext( 'The directory for the PID file “[_1]” does not exist.', $pidfile );
                            return;
                        }
                        if ( -e $pidfile && open( my $fh, '<', $pidfile ) ) {
                            my $data = do { local $/; <$fh> };
                            close $fh;
                            chomp $data;
                            if ( $data && $data !~ /\A\d+\z/ ) {
                                $logger->info("data is '$data'");
                                $metadata->{'result'} = 0;
                                $metadata->{'reason'} = _locale()->maketext( 'The pid file “[_1]” already exists and contains non-digit characters. Remove the file first if you really wish to use this file as the pid file.', $pidfile );
                                return;
                            }
                        }
                    }
                    else {    # Because rel. paths already filtered, the match must have failed due to a trailing slash, or it points to an extant directory. Either way...
                        $metadata->{'result'} = 0;
                        $metadata->{'reason'} = _locale->maketext( 'The PID file “[_1]” cannot be a directory.', $pidfile );
                        return;
                    }
                }
                $spamd_conf->{$option} = $formref->{$option};
            }
            else {
                $metadata->{'result'} = 0;
                $metadata->{'reason'} = _locale()->maketext( '“[_1]” is not a valid value for “[_2]”.', $formref->{$option}, $option );
                return;
            }
        }
        else {
            delete( $spamd_conf->{$option} );
        }
    }

    # Write spamd_conf out to file.
    unless ( _flush_config( $spamd_conf, _get_spamd_conf_file() ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = _locale()->maketext( 'The system was unable to save the settings for “[_1]”.', 'spamd' );
        return;
    }

    _restart_spamd();

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = _locale()->maketext('OK');
    return;
}

sub _is_valid_option {
    my ( $option, $validator ) = @_;

    if ( ref $validator eq 'CODE' ) {
        return $validator->($option);
    }
    return $option =~ /^$validator$/;
}

sub _load_current_config {
    my $spamd_conf = {};
    Cpanel::Config::LoadConfig::loadConfig( _get_spamd_conf_file(), $spamd_conf, '\s*=\s*', '^[\s\t]*#', undef, 0 );
    return $spamd_conf;
}

sub _get_spamd_conf_file {
    return '/etc/cpspamd.conf';
}

sub _get_spamd_options {
    return {
        'allowedips' => sub {
            my ($val) = @_;
            foreach my $ip_cidr ( split /,/, $val ) {
                return 0 unless Cpanel::Validate::IP::is_valid_ip_cidr_or_prefix($ip_cidr);
            }
            return 1;
        },
        'maxconnperchild' => qr/\d+/,
        'maxchildren'     => qr/\d+/,
        'pidfile'         => qr/[^\0]+/,
        'timeouttcp'      => qr/\d+/,
        'timeoutchild'    => qr/\d+/,
    };
}

sub _flush_config {
    my ( $conf_ref, $conf_file ) = @_;

    my $fh;
    my $flock = Cpanel::SafeFile::safeopen( $fh, '>', $conf_file );

    unless ($flock) {
        $logger->warn("Unable to save spamd settings to $conf_file");
        return;
    }

    foreach my $opt ( sort keys( %{$conf_ref} ) ) {
        print {$fh} $opt, '=', $conf_ref->{$opt}, "\n";
    }

    Cpanel::SafeFile::safeclose( $fh, $flock );
    return 1;
}

sub _restart_spamd {
    $logger->info("Restarting Exim and Spamd");
    Cpanel::SafeRun::Errors::saferunnoerror("/usr/local/cpanel/scripts/restartsrv_exim");
    return;
}

1;
