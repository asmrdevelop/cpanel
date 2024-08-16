package Cpanel::Config::CpConfGuard::Validate;

# cpanel - Cpanel/Config/CpConfGuard/Validate.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

no warnings 'numeric';    # we need to force some numeric conversions

# For dynamic default fallback.
use Cpanel::Config::CpConfGuard::Default ();
use Cpanel::Server::Type                 ();
use Cpanel::Crypt::GPG::Settings         ();

sub patch_cfg {
    my ($cfg) = @_;

    return unless defined $cfg && ref $cfg eq 'HASH';

    my $invalid = {};

    _patch_cycle( $cfg, $invalid );
    _patch_bwcycle( $cfg, $invalid );
    _patch_minpwstrength( $cfg, $invalid );
    _migrate_tweak_settings( $cfg, $invalid );
    _validate_rpm_settings( $cfg, $invalid );
    _set_binary_settings( $cfg, $invalid );
    _set_min_max_settings( $cfg, $invalid );
    _set_dnsonly_settings( $cfg, $invalid );
    _set_signature_validation( $cfg, $invalid );

    # should be last
    _validate_values_from_list( $cfg, $invalid );

    return $invalid;
}

{
    my $default;

    sub _default {
        return $default if $default;
        $default = Cpanel::Config::CpConfGuard::Default->new();
        return $default;
    }
}

sub _validate_values_from_list {
    my ( $cfg, $invalid ) = @_;

    return unless $cfg && ref $cfg eq 'HASH';

    # currently only static values
    my $valid_values_for = {
        cookieipvalidation => [qw/disabled strict loose/],
    };

    my $defaults = Cpanel::Config::CpConfGuard::Default::default_statics();

    foreach my $k ( keys %$valid_values_for ) {

        # do nothing when key does not exist
        next unless exists $cfg->{$k};

        # correct an undefined or wrong value
        next if defined $cfg->{$k} && grep { $cfg->{$k} eq $_ } @{ $valid_values_for->{$k} };
        next if !exists $defaults->{$k};
        my $new_value = $defaults->{$k};

        # need to preserve original from value
        $invalid->{$k} = { 'from' => $cfg->{$k}, 'to' => $new_value };
        $cfg->{$k}     = $new_value;
    }

    return;
}

sub _validate_rpm_settings {
    my ( $cfg, $invalid ) = @_;

    # RPM packages #
    my $orig_nameserver = $cfg->{'local_nameserver_type'};
    $cfg->{'local_nameserver_type'} ||= '';
    $cfg->{'local_nameserver_type'} = strip_whitespace( $cfg->{'local_nameserver_type'} );
    if ( $cfg->{'local_nameserver_type'} !~ /^(?:bind|powerdns|disabled)$/ ) {
        $cfg->{'local_nameserver_type'}     = _default->get_static_default_for('local_nameserver_type');
        $invalid->{'local_nameserver_type'} = { from => $orig_nameserver, to => $cfg->{'local_nameserver_type'} };
    }

    my $orig_mailserver = $cfg->{'mailserver'};
    $cfg->{'mailserver'} ||= '';
    $cfg->{'mailserver'} = strip_whitespace( $cfg->{'mailserver'} );
    if ( $cfg->{'mailserver'} !~ /^(?:dovecot|disabled)$/ ) {
        $cfg->{'mailserver'}     = _default->compute_mailserver();
        $invalid->{'mailserver'} = { from => $orig_mailserver, to => $cfg->{'mailserver'} };
    }

    my $orig_ftpserver = $cfg->{'ftpserver'};
    $cfg->{'ftpserver'} ||= '';
    $cfg->{'ftpserver'} = strip_whitespace( $cfg->{'ftpserver'} );
    if ( $cfg->{'ftpserver'} !~ /^(?:pure-ftpd|proftpd|disabled)$/ ) {
        $cfg->{'ftpserver'}     = _default->compute_ftpserver();
        $invalid->{'ftpserver'} = { from => $orig_ftpserver, to => $cfg->{'ftpserver'} };
    }

    return 1;
}

sub strip_whitespace {
    my $string = shift;
    return unless defined $string;
    $string =~ s/^\s*//;
    $string =~ s/\s*$//;
    return $string;
}

# Convert bwcycle to non-zero float accurate to .25 precision
sub _patch_cycle {
    my ( $cfg, $invalid ) = @_;

    my $original = $cfg->{'cycle_hours'};

    # Force it into a number before we do anything.
    $cfg->{'cycle_hours'} = ( $cfg->{'cycle_hours'} || 0 ) + 0;
    $cfg->{'cycle_hours'} ||= 24;

    # Round to .25 accuracy.
    my $new_cycle_hours = int( $cfg->{'cycle_hours'} * 4 + 0.5 ) / 4;
    $cfg->{'cycle_hours'} = $new_cycle_hours;

    # No change.
    return 0 if ( defined $original && $original eq $cfg->{'cycle_hours'} );    # use str comparison

    $invalid->{'cycle_hours'} = { 'from' => $original, 'to' => $cfg->{'cycle_hours'} };
    return 1;
}

# Convert bwcycle to a float accurate to .25 precision
sub _patch_bwcycle {
    my ( $cfg, $invalid ) = @_;

    my $original = $cfg->{'bwcycle'};

    # Force it into a number before we do anything.
    $cfg->{'bwcycle'} = ( $cfg->{'bwcycle'} || 0 ) + 0;

    # Convert bwcycle to be accurate to .25 precision
    $cfg->{'bwcycle'} = int( $cfg->{'bwcycle'} * 4 + 0.5 ) / 4;
    $cfg->{'bwcycle'} ||= 2;

    # Nothing changed.
    return 0 if defined $original && $original eq $cfg->{'bwcycle'};    # use str comparison

    # Report the change.
    $invalid->{'bwcycle'} = { 'from' => $original, 'to' => $cfg->{'bwcycle'} };
    return 1;
}

sub _patch_minpwstrength {
    my ( $cfg, $invalid ) = @_;

    my $original = $cfg->{'minpwstrength'};

    # Force it into a number before we do anything.
    $cfg->{'minpwstrength'} = ( $cfg->{'minpwstrength'} || 0 ) + 0;

    $cfg->{'minpwstrength'} = 5 * int( 0.5 + $cfg->{'minpwstrength'} / 5 );

    return 0 if defined $original && $original eq $cfg->{'minpwstrength'};    # use str comparison

    $invalid->{minpwstrength} = { from => $original, to => $cfg->{'minpwstrength'} };
    return 1;
}

# code from bin/migrate_tweak_settings
sub _migrate_tweak_settings {
    my ( $cfg, $invalid ) = @_;

    my @zeros_to_migrate = qw(
      emailusers_diskusage_warn_percent
      emailusers_diskusage_critical_percent
      emailusers_diskusage_full_percent
      emailusers_mailbox_warn_percent
      emailusers_mailbox_critical_percent
      emailusers_mailbox_full_percent
      tcp_check_failure_threshold
    );

    foreach my $old_zero_setting (@zeros_to_migrate) {
        if ( defined $cfg->{$old_zero_setting}
            && $cfg->{$old_zero_setting} == 0 ) {
            $invalid->{$old_zero_setting} = { 'from' => $cfg->{$old_zero_setting}, 'to' => undef };
            $cfg->{$old_zero_setting}     = undef;
        }
    }

    if ( $cfg->{'numacctlist'} && $cfg->{'numacctlist'} =~ m{all}i ) {
        $invalid->{'numacctlist'} = { 'from' => $cfg->{'numacctlist'}, 'to' => undef };
        $cfg->{'numacctlist'}     = undef;
    }

    if ( defined $cfg->{'dnsadminapp'} && $cfg->{'dnsadminapp'} eq q{} ) {
        $invalid->{'dnsadminapp'} = { 'from' => '', 'to' => undef };
        $cfg->{'dnsadminapp'}     = undef;
    }

    if (
        defined $cfg->{'file_upload_max_bytes'}
        && (  !$cfg->{'file_upload_max_bytes'}
            || $cfg->{'file_upload_max_bytes'} =~ m{unlimited}i )
    ) {
        $invalid->{'file_upload_max_bytes'} = { 'from' => $cfg->{'file_upload_max_bytes'}, 'to' => undef };
        $cfg->{'file_upload_max_bytes'}     = undef;
    }

    if ( defined $cfg->{'maxemailsperhour'} && $cfg->{'maxemailsperhour'} == 0 ) {
        $invalid->{'maxemailsperhour'} = { 'from' => $cfg->{'maxemailsperhour'}, 'to' => undef };
        $cfg->{'maxemailsperhour'}     = undef;
    }

    if ( defined $cfg->{'emailsperdaynotify'} && $cfg->{'emailsperdaynotify'} == 0 ) {
        $invalid->{'emailsperdaynotify'} = { 'from' => $cfg->{'emailsperdaynotify'}, 'to' => undef };
        $cfg->{'emailsperdaynotify'}     = undef;
    }

    if ( exists $cfg->{'cookieipvalidation'} ) {
        if ( $cfg->{'cookieipvalidation'} eq '0' ) {
            $cfg->{'cookieipvalidation'}     = 'disabled';
            $invalid->{'cookieipvalidation'} = { 'from' => 0, 'to' => 'disabled' };
        }
        elsif ( $cfg->{'cookieipvalidation'} eq '1' ) {
            $cfg->{'cookieipvalidation'}     = 'strict';
            $invalid->{'cookieipvalidation'} = { 'from' => 1, 'to' => 'strict' };
        }

        # valid possible values are checked later
    }

    if ( defined $cfg->{'maxcpsrvdconnections'} && int( $cfg->{'maxcpsrvdconnections'} ) < 200 ) {
        $invalid->{'maxcpsrvdconnections'} = { 'from' => $cfg->{'maxcpsrvdconnections'}, 'to' => 200 };
        $cfg->{'maxcpsrvdconnections'}     = 200;
    }

    if ( $cfg->{'overwritecustomproxysubdomains'} ) {
        $cfg->{'proxysubdomainsoverride'} = 0;
    }

    # ZendOpt is not supported on php 7.0+
    if ( $cfg->{'phploader'} && index( $cfg->{'phploader'}, 'zendopt' ) != -1 ) {
        my $old  = $cfg->{'phploader'};
        my @opts = grep { $_ ne 'zendopt' } split( /,/, $cfg->{'phploader'} );
        $cfg->{'phploader'}     = join( ',', @opts );
        $invalid->{'phploader'} = { 'from' => $old, 'to' => "$cfg->{'phploader'}" };

    }

    return 1;
}

# Some settings don't make sense on DNSONLY.  Force them to a specific value.
sub _set_dnsonly_settings {
    my ( $cfg, $invalid ) = @_;

    return unless Cpanel::Server::Type::is_dnsonly();

    my %options = (
        'popbeforesmtp' => 0,
    );

    foreach my $key ( keys %options ) {
        if ( !defined $cfg->{$key} ) {
            $cfg->{$key}     = $options{$key};
            $invalid->{$key} = { 'from' => undef, 'to' => $cfg->{$key} };
        }
        elsif ( $cfg->{$key} ne $options{$key} ) {
            my $old = $cfg->{$key};
            $cfg->{$key}     = $options{$key};
            $invalid->{$key} = { 'from' => $old, 'to' => $cfg->{$key} };
        }
    }
    return;
}

# Helper test routine to determine what keys are normalized to 0 or 1
sub get_binary_variables_validated {
    return qw{ maintenance_rpm_version_check maintenance_rpm_version_digest_check };
}

sub _set_binary_settings {
    my ( $cfg, $invalid ) = @_;

    # RPM tweaks #
    foreach my $key ( get_binary_variables_validated() ) {
        if ( !defined $cfg->{$key} ) {
            $cfg->{$key}     = 0;
            $invalid->{$key} = { 'from' => undef, 'to' => $cfg->{$key} };
        }
        elsif ( $cfg->{$key} =~ m/(yes|on|true)/i ) {
            $cfg->{$key}     = 1;
            $invalid->{$key} = { 'from' => $1, 'to' => $cfg->{$key} };
        }
        elsif ( $cfg->{$key} =~ m/(no|off|false)/i ) {
            $cfg->{$key}     = 0;
            $invalid->{$key} = { 'from' => $1, 'to' => $cfg->{$key} };
        }
        elsif ( $cfg->{$key} =~ m/^(00+)$/i ) {
            $cfg->{$key}     = 0;
            $invalid->{$key} = { 'from' => $1, 'to' => $cfg->{$key} };
        }
        elsif ( $cfg->{$key} !~ m/^[01]$/ ) {
            my $old = $cfg->{$key};
            $cfg->{$key}     = $cfg->{$key} ? 1 : 0;
            $invalid->{$key} = { 'from' => $old, 'to' => $cfg->{$key} };
        }
    }
    return;
}

sub _set_signature_validation {
    my ( $cfg, $invalid ) = @_;

    my $validation_setting = Cpanel::Crypt::GPG::Settings::validation_setting_fixup( $cfg->{signature_validation} );

    if ( !defined $cfg->{signature_validation} || $cfg->{signature_validation} ne $validation_setting ) {
        $invalid->{signature_validation} = { 'from' => $cfg->{signature_validation}, 'to' => $validation_setting };
        $cfg->{signature_validation}     = $validation_setting;
    }

    if ( !defined $cfg->{verify_3rdparty_cpaddons} || $cfg->{verify_3rdparty_cpaddons} !~ m/^[01]$/ ) {
        $invalid->{verify_3rdparty_cpaddons} = { 'from' => $cfg->{verify_3rdparty_cpaddons}, 'to' => '0' };
        $cfg->{verify_3rdparty_cpaddons}     = '0';
    }

    return;
}

my %min_max = (
    php_max_execution_time  => { minimum => 90,   maximum => 500 },
    php_memory_limit        => { minimum => 128,  maximum => 16384 },
    php_post_max_size       => { minimum => 55,   maximum => 2047 },
    php_upload_max_filesize => { minimum => 50,   maximum => 2047 },
    transfers_timeout       => { minimum => 1800, maximum => 172800 },
    gzip_compression_level  => { minimum => 1,    maximum => 9 },
    gzip_pigz_block_size    => { minimum => 128,  maximum => 524288 },
    gzip_pigz_processes     => { minimum => 1,    maximum => 128 },
    upcp_log_retention_days => { minimum => 3,    maximum => 999 },
);

# Helper test routine to determine what keys are min/max validated right now.
sub get_min_max_settings {
    my %settings = %min_max;
    return \%settings;
}

sub _set_min_max_settings {
    my ( $cfg, $invalid ) = @_;
    my $default = _default();

    foreach my $key ( keys %min_max ) {
        my $current_value = $cfg->{$key};

        # Set it to the default if the current value doesn't look like a number (supports scientific notation for big numbers)
        if ( !defined $current_value || $current_value !~ /^-?(?:[0-9]+|[0-9]e[-+][0-9]+)\s*$/ ) {
            my $default_value = $default->get_static_default_for($key);
            $invalid->{$key} = { 'from' => $current_value, 'to' => $default_value };
            $current_value = $cfg->{$key} = $default_value;
        }

        # Set minimum but only if it's provided.
        if ( exists $min_max{$key}->{minimum} ) {
            my $minimum = $min_max{$key}->{minimum};
            if ( $current_value < $minimum ) {
                $invalid->{$key} = { 'from' => $current_value, 'to' => $minimum };
                $current_value = $cfg->{$key} = $minimum;
            }
        }

        # Set maximum but only if it's provided.
        if ( exists $min_max{$key}->{maximum} ) {
            my $maximum = $min_max{$key}->{maximum};
            if ( $current_value > $maximum ) {
                $invalid->{$key} = { 'from' => $current_value, 'to' => $maximum };
                $cfg->{$key}     = $maximum;
            }
        }
    }
    return;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Cpanel::Config::CpConfGuard::Validate

=head1 SYNOPSIS

  my $invalid = Cpanel::Config::CpConfGuard::Validate::patch_cfg( $cpanel_config_hash );

=head1 DESCRIPTION

Used by CpConfGuard to validate the loaded values from /var/cpanel/cpanel.config and fix them when needed.

=head1 METHODS

=head2 patch_cfg

This is the only public interface. Pass in the hash ref representing cpanel.config and it will
be corrected as needed.

A hash is returned from this subroutine indicating what was fixed. This is primarily used by
CpConfGuard to generate notification emails indication what was changed.

=head1 Private METHODS

=head2 strip_whitespace

Assuming what was passed in was a string, the leading and trailing white space is removed.

=head2 _default

Gives this package access to a CpConfGuard::Default object so dynamic values can be calculated
when they do not match spec.

=head2 _validate_rpm_settings

Used to be sure that all keys that control RPM installation settings in cpanel.config are valid.

B<NOTE:> Due to upgrade blocker changes in 11.44, we explicitly removed validation of mysql-version

=head2 _patch_cycle

This deals with some magic that used to be performed on cpanel.config to upgrade cycle and cycle_hours.
It was done in Cpanel/Config/PatchCpConf.pm, a early prototype of this module. We changed the behavior
of these variables at some point and this code was put there to upgrade and then keep the variables
semi-sane.

=head2 _patch_bwcycle

More validation and accuracy fixers for the bwcycle cpanel.config setting, also from Cpanel/Config/PatchCpConf.pm

=head2 _patch_minpwstrength

Validates minpwstrength. Also from Cpanel/Config/PatchCpConf.pm

=head2 _migrate_tweak_settings

Takes some validation that was in Whostmgr/TweakSettings/Main.pm and moves it into this centralized location.

=head2 _set_min_max_settings

We have many places where we want to enforce a minimum and maximum threshold for cpanel.config.
This subroutine currently validates:

=head2 get_min_max_settings

This is a helper subroutine for unit tests so we know what's currently being validated.

=head2 get_binary_variables_validated

This is a helper subroutine for unit tests so we know what true/false variables are currently being validated.

=over 2

=item php_max_execution_time, php_memory_limit, php_post_max_size, php_upload_max_filesize

  These are also validated in bin/checkphpini, but this is the more centralized location now.

=back

=cut
