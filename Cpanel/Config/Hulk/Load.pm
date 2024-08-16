package Cpanel::Config::Hulk::Load;

# cpanel - Cpanel/Config/Hulk/Load.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule               ();
use Cpanel::Config::LoadConfig::Tiny ();
use Cpanel::Config::Hulk             ();

our $cphulkd_conf_cache_ref;
our $DEFAULT_LOGIN_LOOKBACK_TIME = ( 60**2 * 6 );    # 6 HOURS
our $CONF_PERMS                  = 0644;

# This hash defines the 'default' values for each of the cPHulk settings.
# If one of these directives is missing in the conf file, the specified default
# is used.
my %cphulk_conf_integer_defaults = (
    'ip_brute_force_period_mins' => 15,     # IP Address-based Brute Force Protection Period - amount of time the 'temporary' blocks per IP will last.
    'brute_force_period_mins'    => 5,      # Brute Force Protection Period - amount of time the 'temporary' lockouts per user will last.
    'lookback_period_min'        => 360,    # Duration for Retaining Failed Logins
    'max_failures'               => 15,     # Maximum Failures per Account - will trigger a user-level lockout if this limit is reached.
    'max_failures_byip'          => 5,      # Maximum Failures per IP Address - will trigger a temp IP block once this limit is reached.
    'mark_as_brute'              => 30,     # Maximum Failures per IP Address before the IP Address is Blocked for One Day
);

my %cphulk_conf_string_defaults = (
    'command_to_run_on_brute_force'           => '',
    'command_to_run_on_excessive_brute_force' => '',
);

my %cphulk_conf_boolean_defaults = (
    'block_brute_force_with_firewall'           => 0,    # Block IP addresses at the firewall level if they trigger brute force protection
    'block_excessive_brute_force_with_firewall' => 1,    # Block IP addresses at the firewall level if they trigger a one-day block
    'notify_on_root_login'                      => 0,    # Send a notification upon successful root login when the IP address is not on the whitelist
    'notify_on_root_login_for_known_netblock'   => 0,    # Send a notification upon successful root login when the IP address is not on the whitelist, but from a known netblock
    'notify_on_brute'                           => 0,    # Send a notification when the system detects a brute force user
    'username_based_protection'                 => 0,    # Enable username based protection on all requests
    'ip_based_protection'                       => 1,    # Enable IP based protection on all requests
    'username_based_protection_local_origin'    => 1,    # Enable username based protection only on requests originating from a Local IP
    'username_based_protection_for_root'        => 0,    # Allow root to be locked out with username based protection
);

#NOTE: This will warn() if cPHulk config is out of whack.
#
sub loadcphulkconf {
    my $filesys_mtime = 0;

    my $conf_file = Cpanel::Config::Hulk::get_conf_file();
    if ( -e $conf_file ) {
        $filesys_mtime = ( stat(_) )[9];
    }

    if ( $cphulkd_conf_cache_ref && exists $cphulkd_conf_cache_ref->{'mtime'} && $filesys_mtime == $cphulkd_conf_cache_ref->{'mtime'} ) {
        return $cphulkd_conf_cache_ref->{'conf'};
    }

    my %cphulk_conf;

    if ($filesys_mtime) {
        Cpanel::Config::LoadConfig::Tiny::loadConfig( $conf_file, \%cphulk_conf );
    }

    ensure_defaults( \%cphulk_conf );

    $cphulkd_conf_cache_ref = { 'mtime' => $filesys_mtime, 'conf' => \%cphulk_conf };

    return wantarray ? %cphulk_conf : \%cphulk_conf;
}

sub clear_cache {
    undef $cphulkd_conf_cache_ref;
    return 1;
}

sub get_cphulk_conf_transaction {
    my $conf_file = Cpanel::Config::Hulk::get_conf_file();

    Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::LoadConfig');
    my $trans_obj       = Cpanel::Transaction::File::LoadConfig->new( 'path' => $conf_file, 'delimiter' => '=', 'permissions' => 0600 );
    my $cphulk_conf_ref = $trans_obj->get_data() || {};
    ensure_defaults($cphulk_conf_ref);

    return $trans_obj;
}

#NOTE: This both plugs in defaults for missing values AND massages existing
#values to conform to the right length/format.
#
sub ensure_defaults {
    my ($conf_ref) = @_;

    # For non-booleans, we need to set a max length on the value, otherwise the value could end up as "inf"
    # when we convert to an int. The max length was chosen to be 6 since that could account for the number of
    # minutes in a year and for 999,999 failures.
    foreach my $key ( keys %cphulk_conf_integer_defaults ) {
        $conf_ref->{$key} = exists $conf_ref->{$key} && length $conf_ref->{$key} ? int substr( $conf_ref->{$key}, 0, $Cpanel::Config::Hulk::MAX_LENGTH ) : $cphulk_conf_integer_defaults{$key};
    }

    foreach my $key ( keys %cphulk_conf_boolean_defaults ) {
        $conf_ref->{$key} = exists $conf_ref->{$key} ? int $conf_ref->{$key} : $cphulk_conf_boolean_defaults{$key};
    }

    foreach my $key ( keys %cphulk_conf_string_defaults ) {
        $conf_ref->{$key} ||= $cphulk_conf_string_defaults{$key};
    }

    #----------------------------------------------------------------------
    # Caculated values
    $conf_ref->{'brute_force_period_sec'}    = ( 60 * $conf_ref->{'brute_force_period_mins'} );
    $conf_ref->{'ip_brute_force_period_sec'} = ( 60 * $conf_ref->{'ip_brute_force_period_mins'} );

    $conf_ref->{'lookback_time'} = defined $conf_ref->{'lookback_period_min'} ? ( 60 * $conf_ref->{'lookback_period_min'} ) : undef;
    $conf_ref->{'lookback_time'} ||= $conf_ref->{'brute_force_period_sec'} > $DEFAULT_LOGIN_LOOKBACK_TIME ? $conf_ref->{'brute_force_period_sec'} : $DEFAULT_LOGIN_LOOKBACK_TIME;

    # Always taken from the state of the flag file
    $conf_ref->{'is_enabled'} = Cpanel::Config::Hulk::is_enabled() || 0;

    return $conf_ref;
}

1;
