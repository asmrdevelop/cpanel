package Cpanel::Rlimit;

# cpanel - Cpanel/Rlimit.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Config::LoadCpConf ();
use Cpanel::Maxmem             ();
use Cpanel::Sys::Rlimit        ();

# No Try::Tiny for memory

###########################################################################
#
# Method:
#   set_rlimit
#
# Description:
#   Sets the rlimits for RSS, AS, and CORE.
#   If an rlimit value (number of pages of ram) is passed in the rlimit
#   is set to that value.  If no value is passed, the server default
#   is used.  The rlimit for CORE is set to 0 if the system
#   has disabled 'coredump' in the cpanel config.
#
# Parameters:
#   $limit - The number of pages of ram to use for RLIMIT_RSS and RLIMIT_AS
#   $limit_names - Arrayref of the limits to modify (defaults to [qw/RSS AS/])
#
# Exceptions:
#   Trapped and logged with Cpanel::Logger
#
# Returns:
#		0 - Failed to set rlimit
#		1 - Rlimit set
#
# see setrlimit(2) for more information;
#
sub set_rlimit {
    my ( $limit,          $limit_names )          = @_;
    my ( $default_rlimit, $coredump_are_enabled ) = _get_server_setting_or_default();

    $limit       ||= $default_rlimit || $Cpanel::Sys::Rlimit::RLIM_INFINITY;
    $limit_names ||= [qw/RSS AS/];
    my $core_limit = $coredump_are_enabled ? $limit : 0;

    if ( $limit > $Cpanel::Sys::Rlimit::RLIM_INFINITY ) {
        require Cpanel::Logger;
        Cpanel::Logger->new->warn("set_rlimit adjusted the requested limit of “$limit” to infinity because it exceeded the maximum allowed value.");
        $limit = $Cpanel::Sys::Rlimit::RLIM_INFINITY;
    }
    my $error = '';

    # NOTE: a limit of 0 means infinity
    foreach my $lim (@$limit_names) {
        local $@;
        eval { Cpanel::Sys::Rlimit::setrlimit( $lim, $limit, $limit ) } or do {
            my $limit_human_value = ( $limit == $Cpanel::Sys::Rlimit::RLIM_INFINITY ? 'INFINITY' : $limit );
            $error .= "$$: Unable to set RLIMIT_$lim to $limit_human_value: $@\n";
        }
    }
    local $@;
    eval { Cpanel::Sys::Rlimit::setrlimit( 'CORE', $core_limit, $core_limit ) }
      or $error .= "$$: Unable to set RLIMIT_CORE to $core_limit: $@\n";

    if ($error) {
        $error =~ s/\n$//;
        require Cpanel::Logger;
        Cpanel::Logger->new->warn($error);
        return 0;
    }

    return 1;
}

###########################################################################
#
# Method:
#   set_min_rlimit
#
# Description:
#   Sets the rlimits for RSS, AS to the value passed in
#   if they are curerntly set to lower values.
#
# Parameters:
#   $min - The minimum number of pages of ram to use for RLIMIT_RSS and RLIMIT_AS
#
# Exceptions:
#   Trapped and logged with Cpanel::Logger
#
# Returns:
#		0 - Failed to set rlimit
#		1 - Rlimit set
#
# see setrlimit(2) for more information;
#
sub set_min_rlimit {
    my ($min) = @_;

    my $error = '';
    foreach my $lim (qw(RSS AS)) {
        my ( $current_soft, $current_hard ) = Cpanel::Sys::Rlimit::getrlimit($lim);
        if ( $current_soft < $min || $current_hard < $min ) {
            local $@;
            eval { Cpanel::Sys::Rlimit::setrlimit( $lim, $min, $min ) } or $error .= "$$: Unable to set RLIMIT_$lim to $min: $@\n";
        }
    }

    if ($error) {
        $error =~ s/\n$//;
        require Cpanel::Logger;
        Cpanel::Logger->new->warn($error);
        return 0;
    }

    return 1;
}

###########################################################################
#
# Method:
#   get_current_rlimits
#
# Description:
#   Fetch a hashref of the current values for the RSS, AS, and CORE
#   rlimits with the name of each limit as the keys, and the current
#   limit in number of pages as the value.
#
# Parameters:
#   None
#
# Exceptions:
#   Any exception from Cpanel::Sys::Rlimit::getrlimit
#
# Returns:
#	A hashref of the current values.
#   Example:
#   {
#     'RSS'  => 123,
#     'AS'   => 123,
#     'CORE' =>   0,
#   }
#
# see getrlimit(2) for more information;
#
sub get_current_rlimits {
    return { map { $_ => [ Cpanel::Sys::Rlimit::getrlimit($_) ] } (qw(RSS AS CORE)) };
}

###########################################################################
#
# Method:
#   restore_rlimits
#
# Description:
#   Restores rlimits to the values that are passed in via
#   hashref.  This function is intended to take a hashref that was
#   returned from get_current_rlimits, however it can accept
#   any rlimits that Cpanel::Sys::Rlimit knows how to support
#
# Parameters:
#   $limit_hr - A hashref that was provided by get_current_rlimits
#
# Exceptions:
#   Any exception from Cpanel::Sys::Rlimit::getrlimit
#
# Exceptions:
#   Trapped and logged with Cpanel::Logger
#
# Returns:
#		0 - Failed to set rlimit
#		1 - Rlimit set
#
# see setrlimit(2) for more information;
#
sub restore_rlimits {
    my $limit_hr = shift;
    my $error    = '';
    if ( ref $limit_hr eq 'HASH' ) {
        foreach my $resource_name ( keys %{$limit_hr} ) {
            my $values = $limit_hr->{$resource_name};
            if ( ref $values ne 'ARRAY' || scalar @{$values} != 2 ) {
                $error .= "Invalid limit arguments, could not restore resource limit for $resource_name.\n";
                next;
            }
            local $@;
            eval { Cpanel::Sys::Rlimit::setrlimit( $resource_name, $values->[0], $values->[1] ) }
              or $error .= "$$: Unable to set $resource_name to $values->[0] and $values->[1]: $@\n";
        }
    }
    else {
        $error .= "Invalid arguments, could not restore resource limits.\n";
    }
    if ($error) {
        $error =~ s/\n$//;
        require Cpanel::Logger;
        Cpanel::Logger->new->warn($error);
        return 0;
    }
    return 1;
}

###########################################################################
#
# Method:
#   set_rlimit_to_infinity
#
# Description:
#   Sets the rlimits for RSS, AS, and CORE to INFINITY.
#
# Parameters:
#   none
#
# Exceptions:
#   Trapped and logged with Cpanel::Logger
#
# Returns:
#		0 - Failed to set rlimit
#		1 - Rlimit set
#
# see setrlimit(2) for more information;
#
sub set_rlimit_to_infinity {
    return set_rlimit($Cpanel::Sys::Rlimit::RLIM_INFINITY);
}

###########################################################################
#
# Method:
#   set_open_files_to_maximum
#
# Description:
#   Sets the rlimit for NOFILE to INFINITY.
#
# Parameters:
#   none
#
# Exceptions:
#   Trapped and logged with Cpanel::Logger
#
# Returns:
#		0 - Failed to set rlimit
#		1 - Rlimit set
#
# see setrlimit(2) for more information;
#
sub set_open_files_to_maximum {
    my $limit = 1048576;
    if ( open( my $fh, '<', '/proc/sys/fs/nr_open' ) ) {
        $limit = <$fh>;
        chomp($limit);
        close($fh);
    }
    return set_rlimit( $limit, [qw/NOFILE/] );
}

###########################################################################
#
# Method:
#   _get_server_setting_or_default
#
# Description:
#   Fetch the maxmem and coredump setting from cpanel config, raise them
#   to meet the system minimums, and convert them to number of pages
#   so they can be easily passed to setrlimit.
#
# Parameters:
#   none
#
# Exceptions:
#   None
#
# Returns:
# 	 (
#        Default value for RSS and AS,
#        0 or 1 if coredumps are enabled
#    )
#
sub _get_server_setting_or_default {
    my $cpconf             = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my $default_maxmem     = Cpanel::Maxmem::default();
    my $core_dumps_enabled = $cpconf->{'coredump'};
    my $configured_maxmem  = exists $cpconf->{'maxmem'} ? int( $cpconf->{'maxmem'} || 0 ) : $default_maxmem;

    if ( $configured_maxmem && $configured_maxmem < $default_maxmem ) {
        return ( _mebibytes_to_bytes($default_maxmem), $core_dumps_enabled );
    }
    elsif ( $configured_maxmem == 0 ) {
        return ( $Cpanel::Sys::Rlimit::RLIM_INFINITY, $core_dumps_enabled );
    }
    else {
        return ( _mebibytes_to_bytes($configured_maxmem), $core_dumps_enabled );
    }
}

sub _mebibytes_to_bytes {
    my $mebibytes = shift;
    return ( $mebibytes * 1024**2 );
}

1;
