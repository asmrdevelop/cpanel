package Cpanel::Config::Hulk::Conf;

# cpanel - Cpanel/Config/Hulk/Conf.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule         ();
use Cpanel::Config::Hulk       ();
use Cpanel::Config::Hulk::Load ();
use Cpanel::CountryCodes::IPS  ();
use Cpanel::Exception          ();
use Cpanel::Validate::Boolean  ();
use Cpanel::ServerTasks        ();

use Try::Tiny;

*loadcphulkconf = *Cpanel::Config::Hulk::Load::loadcphulkconf;

my %cphulk_conf_check = (
    'ip_brute_force_period_mins'                => \&_is_valid_block_period_minutes,
    'brute_force_period_mins'                   => \&_is_valid_block_period_minutes,
    'lookback_period_min'                       => \&_is_digit_and_less_than_max_length,
    'max_failures'                              => \&_is_digit_and_less_than_max_length,
    'max_failures_byip'                         => \&_is_digit_and_less_than_max_length,
    'mark_as_brute'                             => \&_is_digit_and_less_than_max_length,
    'country_whitelist'                         => \&_is_valid_country_list,
    'country_blacklist'                         => \&_is_valid_country_list,
    'block_brute_force_with_firewall'           => \&Cpanel::Validate::Boolean::validate_or_die,
    'block_excessive_brute_force_with_firewall' => \&Cpanel::Validate::Boolean::validate_or_die,
    'notify_on_brute'                           => \&Cpanel::Validate::Boolean::validate_or_die,
    'notify_on_root_login'                      => \&Cpanel::Validate::Boolean::validate_or_die,
    'notify_on_root_login_for_known_netblock'   => \&Cpanel::Validate::Boolean::validate_or_die,
    'username_based_protection'                 => \&Cpanel::Validate::Boolean::validate_or_die,
    'username_based_protection_for_root'        => \&Cpanel::Validate::Boolean::validate_or_die,
    'ip_based_protection'                       => \&Cpanel::Validate::Boolean::validate_or_die,
    'username_based_protection_local_origin'    => \&Cpanel::Validate::Boolean::validate_or_die,
);

sub set_single_conf_key {
    my ( $key, $value ) = @_;
    my $trans_obj = Cpanel::Config::Hulk::Load::get_cphulk_conf_transaction();
    if ( $cphulk_conf_check{$key} ) {
        try { $cphulk_conf_check{$key}($value) }
        catch {
            my $errstr = $_;
            $trans_obj->close_or_die();
            die Cpanel::Exception::create( 'InvalidParameter', "Invalid setting for “[_1]”: [_2]", [ $key, Cpanel::Exception::get_string_no_id($errstr) ] );
        };
    }
    my $old_conf_ref = $trans_obj->get_data();
    $old_conf_ref->{$key} = $value;

    _pre_save_tasks($old_conf_ref);

    $trans_obj->save_and_close_or_die(

        # Schedule the task inside the callback so that we never have
        # a state where the transaction is saved but the task is not
        # queued.
        validate_cr => sub {

            if ( $key eq 'country_blacklist' || $key eq 'country_whitelist' ) {
                Cpanel::ServerTasks::schedule_task( ['cPHulkTasks'], 10, 'update_country_ips' );
            }

            return 1;
        },
    );

    return;
}

sub savecphulkconf {
    my $new_conf_ref = shift;

    my $trans_obj          = Cpanel::Config::Hulk::Load::get_cphulk_conf_transaction();
    my $old_conf_ref       = $trans_obj->get_data();
    my $update_country_ips = 0;
    foreach my $key ( keys %{$new_conf_ref} ) {
        next if !exists $cphulk_conf_check{$key};
        try { $cphulk_conf_check{$key}( $new_conf_ref->{$key} ) }
        catch {
            my $errstr = $_;
            $trans_obj->close_or_die();
            die Cpanel::Exception::create( 'InvalidParameter', "Invalid setting for “[_1]”: [_2]", [ $key, Cpanel::Exception::get_string_no_id($errstr) ] );
        };
        $update_country_ips ||= 1 if $key eq 'country_whitelist' || $key eq 'country_blacklist';
    }

    foreach my $key ( keys %cphulk_conf_check ) {
        if ( !exists $new_conf_ref->{$key} || !defined $new_conf_ref->{$key} ) {
            $new_conf_ref->{$key} = $old_conf_ref->{$key};
        }
    }

    _pre_save_tasks($new_conf_ref);
    $trans_obj->set_data($new_conf_ref);

    $trans_obj->save_and_close_or_die(

        # Schedule the task inside the callback so that we never have
        # a state where the transaction is saved but the task is not
        # queued.
        validate_cr => sub {
            if ($update_country_ips) {
                Cpanel::ServerTasks::queue_task( ['cPHulkTasks'], 'update_country_ips' );
            }

            return 1;
        },
    );

    return;
}

sub _pre_save_tasks {
    my ($conf_ref) = @_;

    remove_legacy_config();

    # enabled state is determined by a flag file
    delete $conf_ref->{'is_enabled'};

    Cpanel::Config::Hulk::Load::ensure_defaults($conf_ref);
    _disable_iptables_support_if_not_available($conf_ref);
    Cpanel::Config::Hulk::Load::clear_cache();

    return 1;
}

sub remove_legacy_config {

    # remove configuration from legacy location
    unlink '/var/cpanel/cphulk.conf';
    return;
}

sub _disable_iptables_support_if_not_available {
    my ($args) = @_;

    # We used to do this in the WHMAPI1 module
    # however we always want to make sure we check this
    Cpanel::LoadModule::load_perl_module('Cpanel::XTables::TempBan');
    if ( !try { Cpanel::XTables::TempBan->new( 'chain' => 'cphulk', 'ipversion' => 4 )->can_temp_ban(); } ) {
        $args->{'block_brute_force_with_firewall'}           = 0;
        $args->{'block_excessive_brute_force_with_firewall'} = 0;
    }
    return 1;
}

# Value is between 1 and 1440 (24 hours).
sub _is_valid_block_period_minutes {
    my ($minutes) = @_;
    return 1 if ( defined $minutes && $minutes >= 1 && $minutes <= 1440 );
    die Cpanel::Exception::create( 'InvalidParameter', 'Value must be a number between 1 and 1440.' );
}

# Value is a number between 1 and 999999.
sub _is_digit_and_less_than_max_length {
    my ($val) = @_;
    return 1 if ( defined $val && $val =~ m/^[\d]{1,$Cpanel::Config::Hulk::MAX_LENGTH}+$/ );
    die Cpanel::Exception::create( 'InvalidParameter', 'Must be a number between 0 and 999999.' );
}

sub _is_valid_country_list {
    my ($val) = @_;
    return 1 if !length $val;
    my @countries = split( m{,}, $val );
    foreach my $code (@countries) {
        if ( !Cpanel::CountryCodes::IPS::code_has_entry($code) ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a known [asis,ISO 3166] country code.', [$code] );

        }
    }
    return 1;
}

1;
