package Cpanel::FtpUtils::Config::Proftpd;

# cpanel - Cpanel/FtpUtils/Config/Proftpd.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::FtpUtils::Config );

use Cpanel::Debug                              ();
use Cpanel::LoadModule                         ();
use Cpanel::CachedCommand                      ();
use Cpanel::FileUtils::TouchFile               ();
use Cpanel::FindBin                            ();
use Cpanel::FtpUtils::Config::Proftpd::CfgFile ();
use Cpanel::SSL::Defaults                      ();
use Cpanel::OS                                 ();

# Conf file provides basic settings
# Datastore provides overrides (set in WHM config interface)
#
# We would trust the conf file complely, but we can't guarante it will stay the same
# across upgrades, so the datastore takes precedence.
#
# Very similar to AdvConfig but without a template, and we only store the
# configurable settings in the datastore.

sub new {
    my $class = shift;
    my $self  = $class->SUPER::_init();
    $self->{'managed_settings'} = {
        'cpanelanonymousaccessallowed' => {    # This is only used to pass the anonymous setting, not a valid directive
            'name'    => 'cPanelAnonymousAccessAllowed',
            'context' => {},
            'default' => -e '/var/cpanel/noanonftp' ? 'no' : 'yes',
        },
        'maxinstances' => {
            'name'    => 'MaxInstances',
            'context' => { 'server' => 2, },
            'default' => 'none',
        },
        'timeoutidle' => {
            'name'    => 'TimeoutIdle',
            'context' => { 'server' => 1, },
            'default' => '600',
        },
        'tlsciphersuite' => {
            'name'    => 'TLSCipherSuite',
            'context' => {
                'server'      => 1,
                'virtualhost' => 1,
            },
            'default' => Cpanel::SSL::Defaults::default_cipher_list(),
        },
        'tlsprotocol' => {
            'name'    => 'TLSProtocol',
            'context' => {
                'server' => 1,
            },
            'default' => Cpanel::SSL::Defaults::default_protocol_list( { type => 'positive', delimiter => ' ' } ),
        },
        'tlsrequired' => {
            'name'    => 'TLSRequired',
            'context' => {
                'server'      => 1,
                'virtualhost' => 1,
            },
            'default' => 'off',
        },
        'tlsoptions' => {
            'name'    => 'TLSOptions',
            'context' => {
                'server'      => 1,
                'virtualhost' => 1,
            },
            'default' => 'NoSessionReuseRequired',
        },
        'showsymlinks' => {
            'name'    => 'ShowSymlinks',
            'context' => {
                'server'      => 1,
                'virtualhost' => 1,
            },
            'default' => 'on',
        },
        'factsoptions' => {
            'name'    => 'FactsOptions',
            'context' => {
                'server'      => 1,
                'virtualhost' => 1,
            },
            'default' => 'off',
        },
        'passiveports' => {
            'name'    => 'PassivePorts',
            'context' => { 'global' => 1, },
            'default' => '49152 65534',
        },
        'masqueradeaddress' => {
            'name'    => 'MasqueradeAddress',
            'context' => { 'server' => 1, },
        },
    };

    if ( Cpanel::OS::has_tcp_wrappers() ) {
        $self->{'managed_settings'}{'tcpservicename'} = {
            'name'    => 'TCPServiceName',
            'context' => {
                'server'      => 1,
                'virtualhost' => 1,
            },
            'default' => 'ftp',
        };
        $self->{'managed_settings'}{'tcpaccessfiles'} = {
            'name'    => 'TCPAccessFiles',
            'context' => {
                'server'      => 1,
                'virtualhost' => 1,
            },
            'default' => 'off',
        };
    }
    $self->{'display_name'}    = 'ProFTPD';
    $self->{'type'}            = 'proftpd';
    $self->{'datastore_name'}  = 'proftpd';
    $self->{'remove_settings'} = {};

    unless ( $self->has_ipv6_support() ) {
        $self->{'remove_settings'}->{'useipv6'} = 1;
    }

    return $self;
}

sub find_conf_file {
    my $self = shift;
    return $self->{'conf_file'} if defined $self->{'conf_file'};
    $self->{'conf_file'} = bare_find_conf_file();
    return $self->{'conf_file'};
}

# Provided as non-oo function for FtpUtils to rely on
sub bare_find_conf_file {
    goto &Cpanel::FtpUtils::Config::Proftpd::CfgFile::bare_find_conf_file;
}

sub has_ipv6_support {
    my $self = shift;

    #We only have $exe if the installed FTP server is ProFTPD.
    my $exe = $self->find_executable();
    if ($exe) {
        my $proftpd_settings = Cpanel::CachedCommand::cachedcommand( $exe, '-V' );
        if ( $proftpd_settings =~ /^\s*configure\s+.*--with-ipv6/m ) {
            return 1;
        }
    }
    return 0;
}

sub find_executable {
    my $self = shift;
    return $self->{'exe'} ||= Cpanel::FindBin::findbin(qw(proftpd /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin));
}

sub get_version {
    my $self = shift;
    my $exe  = $self->find_executable();

    my $proftpd_version = Cpanel::CachedCommand::cachedcommand( $exe, '-v' );
    if ( $proftpd_version && $proftpd_version =~ /proftpd\s+version\s+(\S+)/i ) {
        return $1;
    }
    else {
        return;
    }
}

sub read_settings_from_conf_file {
    my $self = shift;

    my $conf_hr   = {};
    my $conf_file = bare_find_conf_file();

    if ( !-e $conf_file || -z _ ) {
        my $display_name = $self->{display_name};
        Cpanel::Debug::log_warn("The $display_name configuration file '$conf_file' is missing or empty.");
        return $conf_hr;
    }

    my $current_context = 'server';
    my $last_context    = 'server';
    my $limit_login;

    $self->_build_context_regexes();
    $conf_hr->{'cPanelAnonymousAccessAllowed'} = 'yes';

    foreach my $line ( split( m{\n}, $self->_slurp_config() ) ) {
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*#/;
        if ( $line =~ /^\s*<(virtualhost|global)/i ) {
            $current_context = lc($1);
        }
        elsif ( $line =~ /^\s*<\/(virtualhost|global)/i ) {
            $current_context = 'server';
        }
        elsif ( $line =~ /^\s*<anonymous/i ) {
            $last_context    = $current_context;
            $current_context = 'anonymous';
        }
        elsif ( $line =~ /^\s*<\/anonymous/i ) {
            $limit_login     = 0;
            $current_context = $last_context;
        }
        elsif ( defined $self->{'context_regex'}{$current_context} && $line =~ /^\s*($self->{'context_regex'}{$current_context})\s+(\S.*)/i ) {
            my $directive = $1;
            my $val       = $2;
            $directive = $self->{'managed_settings'}{ lc($directive) }{'name'};    # Fix cApiTaliZatioN

            # We're treating all the directives as if they were global even though they are probably
            # listed in multiple contexts.  The first listed setting is considered definitive
            $conf_hr->{$directive} = $val unless ( defined $conf_hr->{$directive} );
        }
        elsif ( $current_context eq 'anonymous' && $line =~ /^\s*<limit login/i ) {
            $limit_login = 1;
        }
        elsif ( $limit_login && $line =~ /^\s*<\/limit/i ) {
            $limit_login = 0;
        }
        elsif ( $limit_login && $line =~ /^\s*denyall/i ) {
            $conf_hr->{'cPanelAnonymousAccessAllowed'} = 'no';
        }
    }

    $conf_hr->{'FactsOptions'}   = ( $conf_hr->{'FactsOptions'}   && $conf_hr->{'FactsOptions'} eq 'UseSlink' )                           ? 'on' : 'off';
    $conf_hr->{'TCPAccessFiles'} = ( $conf_hr->{'TCPAccessFiles'} && $conf_hr->{'TCPAccessFiles'} eq '/etc/hosts.allow /etc/hosts.deny' ) ? 'on' : 'off';

    return $conf_hr;

}

sub get_port {
    my $self = shift;

    return $self->{port} if defined $self->{port};

    # we currently do not manage the port
    #    but use it temporarily to read the setting
    # that setting could move to the constructor when we provide a way to updated it
    $self->{'managed_settings'}->{'port'} = {
        'name'    => 'Port',
        'context' => {
            'server' => 1,
        },
        'default' => 21,
    };

    my $cfg  = $self->read_settings_from_conf_file();
    my $port = $cfg->{'Port'} || $self->{'managed_settings'}->{'port'}->{'default'};
    $port =~ s/#.*$//;
    $port =~ s/\s*$//;
    $self->{port} = int($port);

    delete $self->{'managed_settings'}->{'port'};
    return $self->{port};
}

sub _build_context_regexes {
    my $self = shift;
    return if ( $self->{'contexts_built'} );
    my $directive_contexts = {};
    foreach my $directive ( keys %{ $self->{'managed_settings'} } ) {
        foreach my $context ( keys %{ $self->{'managed_settings'}{$directive}{'context'} } ) {
            push @{ $directive_contexts->{$context} }, $directive if $self->{'managed_settings'}{$directive}{'context'}{$context};
        }
    }
    $self->{'context_regex'}{'server'}      = join( '|', @{ $directive_contexts->{'server'} } );
    $self->{'context_regex'}{'global'}      = join( '|', @{ $directive_contexts->{'global'} } );
    $self->{'context_regex'}{'virtualhost'} = join( '|', @{ $directive_contexts->{'virtualhost'} } );
    if ( keys %{ $self->{'remove_settings'} } ) {
        $self->{'remove_regex'} = join( '|', keys %{ $self->{'remove_settings'} } );
    }
    $self->{'contexts_built'} = 1;
    return;
}

sub check_for_unset_defaults {
    my $self    = shift;
    my $conf_hr = shift;

    foreach my $setting ( values %{ $self->{'managed_settings'} } ) {
        unless ( defined $conf_hr->{ $setting->{'name'} } ) {
            $conf_hr->{ $setting->{'name'} } = $setting->{'default'} if exists $setting->{'default'};
        }
    }
    $conf_hr->{'cPanelAnonymousAccessAllowed'} = -e '/var/cpanel/noanonftp' ? 'no' : 'yes';
    return $conf_hr;
}

sub update_config {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my $self        = shift;
    my $settings_hr = shift;
    my $conf_file   = find_conf_file();

    Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::Raw');
    my $trans           = Cpanel::Transaction::File::Raw->new( 'path' => $conf_file, perms => 0600 );
    my %settings        = %{$settings_hr};
    my $current_context = 'server';
    my $last_context    = 'server';
    my $limit_login;
    my $limit_login_seen;
    my $deny_all_seen;
    my $allow_anon = ( defined $settings{'cPanelAnonymousAccessAllowed'} && $settings{'cPanelAnonymousAccessAllowed'} eq 'no' ) ? 0 : 1;
    delete $settings{'cPanelAnonymousAccessAllowed'};
    my $anon_context_seen;
    my $first_virtualhost = 1;
    my %directives_seen   = (
        'server'      => {},
        'virtualhost' => {},
        'global'      => {},
    );

    $self->_build_context_regexes();

    my $new_conf = '';
    foreach my $line ( split( m{^}, ${ $trans->get_data() } ) ) {
        if ( defined $self->{'remove_regex'} && $line =~ /^\s*$self->{'remove_regex'}\s+\S.*$/i ) {
            next;
        }
        if ( $first_virtualhost && $line =~ /^\s*<virtualhost/i ) {
            foreach my $setting ( keys %settings ) {
                my $directive = $self->{'managed_settings'}{ lc($setting) }{'name'};    # Fix cApiTaliZatioN
                if ( $self->{'managed_settings'}{ lc($setting) }{'context'}{'server'} && !$directives_seen{'server'}{$directive} ) {

                    _append_scalar_ref( \$new_conf, $directive, $settings{$setting} );
                    $directives_seen{'server'}{$directive} = 1;
                }
            }
            $current_context = 'virtualhost';
            if ( !$allow_anon && !$anon_context_seen ) {
                $new_conf .= $self->_anonymous_section('');
            }
            $first_virtualhost = 0;
            $anon_context_seen = 0;
        }
        elsif ( $line =~ /^\s*<(virtualhost|global)/i ) {
            $current_context = lc($1);
        }
        elsif ( $line =~ /^(\s*)<\/(virtualhost|global)/i ) {
            my $whitespace       = $1;
            my $previous_context = lc($2);
            foreach my $setting ( keys %settings ) {
                my $directive = $self->{'managed_settings'}{ lc($setting) }{'name'};    # Fix cApiTaliZatioN
                if ( $self->{'managed_settings'}{ lc($setting) }{'context'}{$previous_context} && !$directives_seen{$previous_context}{$directive} ) {

                    _append_scalar_ref( \$new_conf, $directive, $settings{$setting}, $whitespace );
                    $directives_seen{$previous_context}{$directive} = 1;
                }
            }
            $directives_seen{$previous_context} = {};
            $current_context = 'server';
            if ( !$allow_anon && !$anon_context_seen && $previous_context eq 'virtualhost' ) {
                $new_conf .= $self->_anonymous_section('  ');
            }
            $anon_context_seen = 0;
        }
        elsif ( $line =~ /^\s*<anonymous/i ) {
            $anon_context_seen = 1;
            $last_context      = $current_context;
            $current_context   = 'anonymous';
        }
        elsif ( $line =~ /^(\s*)<\/anonymous/i ) {
            my $whitespace = $1;
            if ( !$allow_anon && !$limit_login_seen ) {
                $new_conf .= $self->_limit_login_section( $whitespace . '  ' );
            }
            $limit_login      = 0;
            $limit_login_seen = 0;
            $deny_all_seen    = 0;
            $current_context  = $last_context;
        }
        elsif ( $current_context eq 'anonymous' && $line =~ /^\s*<limit login/i ) {
            $limit_login = 1;
            next if $allow_anon || $limit_login_seen;
        }
        elsif ($limit_login) {
            if ( $line =~ /^(\s*)<\/limit/i ) {
                my $whitespace = $1;
                $limit_login = 0;
                if ( !$allow_anon && !$deny_all_seen ) {
                    $new_conf .= $whitespace . "  DenyAll\n";
                }
                else {
                    next if $limit_login_seen;
                }
                $limit_login_seen = 1;
            }
            elsif ($limit_login_seen) {
                next;
            }
            elsif ( $line =~ /^\s*denyall/i ) {
                $deny_all_seen = 1;
            }
            elsif ( $line =~ /^\s*allowall/i ) {
                next if !$allow_anon;
            }
            next if $allow_anon;
        }
        elsif ( defined $self->{'context_regex'}{$current_context} && $line =~ /^(\s*)($self->{'context_regex'}{$current_context})\s+(\S.*)/i ) {
            my $whitespace = $1;
            my $directive  = $self->{'managed_settings'}{ lc($2) }{'name'};    # Fix cApiTaliZatioN
            if ( defined $settings_hr->{$directive} && !$directives_seen{$current_context}{$directive} ) {
                _append_scalar_ref( \$new_conf, $directive, $settings_hr->{$directive}, $whitespace );
                $directives_seen{$current_context}{$directive} = 1;
                next;
            }
        }

        $new_conf .= $line;
    }

    # If there isn't a virtualhost at all, then insert the server settings at the end.
    if ($first_virtualhost) {
        foreach my $setting ( keys %settings ) {
            my $directive = $self->{'managed_settings'}{ lc($setting) }{'name'};    # Fix cApiTaliZatioN
            if ( $self->{'managed_settings'}{ lc($setting) }{'context'}{'server'} && !$directives_seen{'server'}{$directive} ) {
                _append_scalar_ref( \$new_conf, $directive, $settings{$setting} );
                $directives_seen{'server'}{$directive} = 1;
            }
        }
    }

    $trans->set_data( \$new_conf );
    $trans->save_and_close_or_die();

    if ($allow_anon) {
        unlink '/var/cpanel/noanonftp' if ( -e '/var/cpanel/noanonftp' );
    }
    else {
        Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/noanonftp') unless ( -e '/var/cpanel/noanonftp' );
    }

    return 1;
}

sub _append_scalar_ref {
    my ( $new_conf_sr, $directive, $setting, $ws ) = @_;

    $ws ||= "";

    # We can't have an empty FactsOptions line, so only print it if we want UseSlink.
    if ( $directive eq "FactsOptions" ) {
        $$new_conf_sr .= "${ws}FactsOptions UseSlink\n" if $setting eq "on";
    }
    elsif ( $directive eq "TCPAccessFiles" ) {
        $$new_conf_sr .= "${ws}TCPAccessFiles /etc/hosts.allow /etc/hosts.deny\n" if $setting eq "on";
    }
    else {
        $$new_conf_sr .= "$ws$directive $setting\n";
    }
    return 1;
}

sub _anonymous_section {
    my $self       = shift;
    my $whitespace = shift;
    return "$whitespace<Anonymous ~ftp>\n" . $self->_limit_login_section( $whitespace . '  ' ) . "$whitespace</Anonymous>\n";
}

sub _limit_login_section {
    my $self       = shift;
    my $whitespace = shift;
    return "$whitespace<Limit LOGIN>\n$whitespace  DenyAll\n$whitespace</Limit>\n";
}

sub set_anon {
    my $self          = shift;
    my $anonymous_ftp = $self->_parse_anon_arg($@);
    my $conf_hr       = $self->load_datastore();
    $conf_hr->{'cPanelAnonymousAccessAllowed'} = $anonymous_ftp ? 'yes' : 'no';

    $self->save_datastore($conf_hr);
    $self->update_config($conf_hr);
}

1;
