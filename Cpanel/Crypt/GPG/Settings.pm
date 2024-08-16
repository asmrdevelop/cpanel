package Cpanel::Crypt::GPG::Settings;

# cpanel - Cpanel/Crypt/GPG/Settings.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::CpConfGuard ();
use Cpanel::Config::Sources     ();
use Cpanel::Exception           ();

our $RELEASE_VALUE     = 'Release Keyring Only';
our $DEVELOPMENT_VALUE = 'Release and Development Keyrings';
our $OFF_VALUE         = 'Off';

our $OLD_DEVELOPMENT_VALUE = 'Release and Test Keyrings';

our $RELEASE_KEYRINGS     = ['release'];
our $DEVELOPMENT_KEYRINGS = [ 'release', 'development' ];
our $OFF_KEYRINGS         = [];

our $SIG_VALIDATION_CPCONF_KEY = 'signature_validation';

sub signature_validation_enabled {
    my $validation_setting = _load_cpconf_setting($SIG_VALIDATION_CPCONF_KEY);
    return ( $validation_setting eq $OFF_VALUE ) ? 0 : 1;
}

sub default_key_categories {
    my $validation_setting = shift || _load_cpconf_setting($SIG_VALIDATION_CPCONF_KEY);

    if ( $validation_setting eq $OFF_VALUE ) {
        return $OFF_KEYRINGS;
    }
    elsif ( $validation_setting eq $DEVELOPMENT_VALUE ) {
        return $DEVELOPMENT_KEYRINGS;
    }
    elsif ( $validation_setting eq $RELEASE_VALUE ) {
        return $RELEASE_KEYRINGS;
    }
    else {
        die Cpanel::Exception->create( 'Invalid signature validation setting: [_1]', [$validation_setting] );
    }
}

sub allowed_digest_algorithms {
    return ('sha512');
}

sub _load_cpconf_setting {
    my $setting = shift;

    # In updatenow it's impossible to rely on CpConfGuard's validation of settings, so this
    # routine forcefully validates the settings we're interested in.
    my $conf = Cpanel::Config::CpConfGuard->new( 'loadcpconf' => 1 )->config_copy;

    if ( $setting eq $SIG_VALIDATION_CPCONF_KEY ) {
        return validation_setting_fixup( $conf->{$setting} );
    }
    else {
        return $conf->{$setting};
    }
}

# Translates the 11.50 version of the development key setting to the 11.52+ version
# and sets the default based on the mirror when the setting is not defined/valid.
sub validation_setting_fixup {
    my $current_setting = shift;
    if ( defined $current_setting && $current_setting eq $OLD_DEVELOPMENT_VALUE ) {
        return $DEVELOPMENT_VALUE;
    }
    elsif ( !defined $current_setting || $current_setting !~ /^(?:\Q$OFF_VALUE\E|\Q$RELEASE_VALUE\E|\Q$DEVELOPMENT_VALUE\E)$/ ) {
        return validation_setting_for_configured_mirror();
    }
    return $current_setting;
}

sub validation_setting_for_configured_mirror {
    my $mirror = Cpanel::Config::Sources::loadcpsources();

    if ( $mirror->{'HTTPUPDATE'} =~ /^(?:.*\.dev|qa-build|next)\.cpanel\.net$/ ) {
        return $DEVELOPMENT_VALUE;
    }
    return $RELEASE_VALUE;
}

1;
