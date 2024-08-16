package Cpanel::PHPFPM::Utils;

# cpanel - Cpanel/PHPFPM/Utils.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule                     ();
use Cpanel::PHPFPM::Controller             ();
use Cpanel::Status                         ();
use Cpanel::Config::LoadUserDomains::Count ();
use Cpanel::Config::userdata::Cache        ();

use constant FIELD_DOMAIN_TYPE => $Cpanel::Config::userdata::Cache::FIELD_DOMAIN_TYPE;

=encoding utf-8

=head1 NAME

Cpanel::PHPFPM::Utils - Miscellaneous utility functions related to Apache w/ PHP-FPM

=head1 SYNOPSIS

    use Cpanel::PHPFPM::Utils;

    my $information_hashref = Cpanel::PHPFPM::Utils::get_fpm_count_and_utilization();
    if( $information_hashref->{'show_warning'} == 1 ) {
        print "This may not be the best idea!\n";
        print "We need to enable " .  $information_hashref->{'domains_to_be_enabled'} . " domains but can only safely support ";
        print $information_hashref->{'number_of_new_fpm_accounts_we_can_handle'} . "\n";
    } else {
        print "This shouldn't crash the server..\n";
    }

    my $user_count = Cpanel::PHPFPM::Utils::get_phpfpm_user_count();
    print "$user_count users configured to use PHP-FPM for all versions installed.\n";

    -or-

    my $user_count = Cpanel::PHPFPM::Utils::get_phpfpm_user_count(70);
    print "$user_count users configured to use PHP-FPM for ea-php70-fpm.\n";

=head1 DESCRIPTION

Miscellaneous functions to support API calls and provide other information that does
not fit elsewhere

=cut

=head2 get_phpfpm_user_count

Returns the number of users on the server configured to use PHP-FPM across all installed versions

=over 2

=item Input (OPTIONAL)

=back

=over 3

=item C<SCALAR>

    The shorthand PHP version to get a count for:

    Example: 56

    my $count = Cpanel::PHPFPM::Controller::get_phpfpm_versions();
    -or-
    my $count = Cpanel::PHPFPM::Controller::get_phpfpm_versions(70);

    If no version is passed, the function will use all installed PHP-FPM versions.

=back

=over 2

=item Output

=back

=over 3

=item C<SCALAR>

    Integer indicating the number of accounts configured for given (or all installed) versions
    if PHP-FPM

    Example: 15

=back

=cut

sub get_phpfpm_user_count {
    my ($version) = @_;
    my $total_users_with_fpm = 0;
    my $vers_ar;

    # Get installed versions
    if ($version) {
        push( @{$vers_ar}, $version );
    }
    else {
        $vers_ar = Cpanel::PHPFPM::Controller::get_phpfpm_versions();
    }
    foreach my $version ( @{$vers_ar} ) {
        my $user_config_count = Cpanel::PHPFPM::Controller::phpfpm_version_users_configured($version);
        $total_users_with_fpm += $user_config_count;
    }
    return $total_users_with_fpm;
}

# Cpanel::Config::LoadUserDomains::Count::countuserdomains()  does same thing this sub used to do, so it is now an alias
*get_total_domains_on_server = *Cpanel::Config::LoadUserDomains::Count::countuserdomains;

=head2 get_total_vhosts_on_server

Returns the total number of active virtual hosts configured on the server.

Unlikely get_total_domains_on_server, this excludes addon domains and parked
domains which are just aliases of main domains or parked domains since they
do not get their own php fpm instance.

=cut

sub get_total_vhosts_on_server {
    require Cpanel::Config::userdata::Cache;
    my $userdata_cache                = Cpanel::Config::userdata::Cache::load_cache();
    my %domain_types_that_have_vhosts = ( 'main' => 1, 'sub' => 1 );
    return scalar grep { $domain_types_that_have_vhosts{ $_->[FIELD_DOMAIN_TYPE] } } values %$userdata_cache;

}

=head2 is_task_still_running

Given a PID and some process info (optional), see if process is still running and matches what we expect

=over 2

=item Output

=back

=over 3

=item C<BOOL>

    1: PID is live and looked like we expected it to
    0: PID doesn't match what we expected, possibly due to being dead.

=back

=cut

sub is_task_still_running {
    my ( $pid, $proc_info ) = @_;
    if ( open( my $task_pidfile, '<', '/proc/' . $pid . '/cmdline' ) ) {
        my $task_proc_cmd = <$task_pidfile>;
        close($task_pidfile);
        chomp($task_proc_cmd);
        if ($proc_info) {
            if ( $task_proc_cmd =~ m/$proc_info/ ) {
                return 1;    # PID is live and matched our task
            }
            else {
                return 0;    # PID is live but didn't match expected process info
            }
        }
        else {
            return 1;        # PID is live and no process info was expected
        }
    }
    return 0;                # PID is dead
}

=head2 get_fpm_count_and_utilization

Returns information designed to help inform an administrator if there is a good chance enabling PHP-FPM by default
will consume all the available memory on their server or not, depending on amount of free memory and number of
accounts that would be converted by the action

=over 2

=item Output

=back

=over 3

=item C<HASHREF>

    {
        'show_warning' => 0,
        'total_domains' => 57,
        'number_of_new_fpm_accounts_we_can_handle' => 96,
        'domains_using_fpm' => 5,
        'domains_to_be_enabled' => 52
    };

=back

=cut

sub get_fpm_count_and_utilization {
    my %info;

    # There is only one FPM instance per vhost (addon and parked domains are excluded)
    my $total_domain_cnt = get_total_vhosts_on_server();
    my ( $domains_using_fpm, undef ) = get_fpm_enabled_domains();
    my $domains_to_be_enabled = $total_domain_cnt - $domains_using_fpm;

    $info{'domains_using_fpm'}     = $domains_using_fpm;
    $info{'total_domains'}         = $total_domain_cnt;
    $info{'domains_to_be_enabled'} = $domains_to_be_enabled;

    my ( $memused, $memtotal, $swapused, $swaptotal ) = Cpanel::Status::memory_totals();
    my $memavail                                 = $memtotal - $memused;
    my $safety_buffer                            = int( $memtotal * .1 );                    # We'll want to leave about 10% ram totally free as a safety buffer
    my $memavail_after_safety                    = $memavail - $safety_buffer;
    my $number_of_new_fpm_accounts_we_can_handle = int( $memavail_after_safety / 30000 );    # factor in about 30MB ram per domain if it has default settings getting hit hard
    $info{'number_of_new_fpm_accounts_we_can_handle'} = $number_of_new_fpm_accounts_we_can_handle;

    if ( $domains_to_be_enabled > $number_of_new_fpm_accounts_we_can_handle ) {
        $info{'show_warning'} = 1;
    }
    else {
        $info{'show_warning'} = 0;
    }

    if ( $info{'show_warning'} == 1 ) {
        my $mem = ( $memavail_after_safety < 0 ) ? 0 : $memavail_after_safety;
        $info{'memory_needed'} = ( $domains_to_be_enabled * 30_000 ) - $mem;
    }
    else {
        $info{'memory_needed'} = 0;
    }

    return \%info;
}

=head2 get_fpm_enabled_domains

Returns the number of domains on the server that already have PHP-FPM enabled

=over 2

=item Output

=back

=over 3

=item C<SCALAR>

    Integer indicating the number of domains already configured to use PHP-FPM

=item C<ARRAYREF>

    Reference to a list of domains that already have PHP-FPM enabled

=back

=cut

sub get_fpm_enabled_domains {
    my $domain_cnt = 0;
    my @domain_list;
    Cpanel::LoadModule::load_perl_module('Cpanel::PHPFPM::Inventory');    # loads File::Glob!
    my $ref = Cpanel::PHPFPM::Inventory::get_inventory();
    foreach my $user ( keys %{$ref} ) {
        if ( ref $ref->{$user} eq 'HASH' and exists( $ref->{$user}{'domains'} ) ) {
            foreach my $domain ( keys %{ $ref->{$user}{'domains'} } ) {
                push( @domain_list, $domain );
                $domain_cnt++;
            }
        }
    }
    return ( $domain_cnt, \@domain_list );
}

1;
