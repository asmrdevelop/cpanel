# cpanel - Whostmgr/Accounts/UpgradeOpportunities.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Accounts::UpgradeOpportunities;

use cPstrict;
use Carp                             ();
use Cpanel::Exception                ();
use Cpanel::Validate::Integer        ();
use Cpanel::Validate::Number         ();
use Cpanel::Locale                   ();
use Whostmgr::DateTime               ();
use Whostmgr::API::1::Utils::Execute ();

use constant DEFAULT_NEARNESS_FRACTION     => 0.75;       # 75% of bandwidth or disk quota
use constant DEFAULT_DISK_THRESHOLD_BLOCKS => 5120000;    # 4.88 GB in 1K blocks

=head1 NAME

Whostmgr::Accounts::UpgradeOpportunities

=head1 FUNCTIONS

=head2 get(%opts)

Returns a hash ref of hash refs representing cPanel accounts mapped to data
representing their upgrade opportunities, and a second hash ref
containing supplementary information such as a "friendly name" map.

An "upgrade opportunity" is a situation where a cPanel account is nearing or
has already exceeded a resource limit, and the server administrator might
want to encourage that user to upgrade to a package with higher limits.

Example:

  {
    user1 => {
      bw_limit => {
        this_month => {
          reached  => 1,
          fraction => 1.01,
        },
        messages = [
          'This account is currently suspended ...',
        ],
        last_month => {
          reached  => 0,
          fraction => 0.89,
        },
      },
      disk_usage => {
        relative_to_quota => {
          reached  => 0,
          fraction => 0.12,
        },
        relative_to_fixed_amount => {
          reached          => 0,
          threshold_blocks => 5120000,
          fraction         => 0.18,
        },
      },
    },
    user2 => {
      ...
    },
    ...
  },
  {
    friendly_name => {
      opportunity => {
        bw_limit => 'Bandwidth Limit',
        ...
      },
      ...
    },
    ...
  }

This structure should remain stable as it's used for producing an API
response.

=head3 ARGUMENTS

=over

=item silence_unlimited - boolean

Do not return disk-related "Upgrade Opportunities" info for unlimited quota
users. This can be used for hosting environments where there is no
availability and/or interest in moving accounts to VPS hosting.

=back

=cut

sub get (%opts) {

    my %supplemental = (
        'friendly_name' => _get_friendly_name_map(),
    );

    # If run outside of API context, this still needs to be defined so the
    # inner implementations know what to do about user ownership.
    local $ENV{REMOTE_USER} = 'root' if !$ENV{REMOTE_USER};

    my $nearness_fraction = delete $opts{nearness_fraction} // DEFAULT_NEARNESS_FRACTION;
    Cpanel::Validate::Number::rational_number($nearness_fraction);
    die Cpanel::Exception::create( 'InvalidParameter', 'nearness_fraction must be a number greater than 0 and less than 1.' ) unless $nearness_fraction > 0 && $nearness_fraction < 1;

    my $disk_threshold_blocks = delete $opts{disk_threshold_blocks} // DEFAULT_DISK_THRESHOLD_BLOCKS;
    Cpanel::Validate::Integer::unsigned( $disk_threshold_blocks, 'disk_threshold_blocks' );

    my $silence_unlimited = delete $opts{silence_unlimited};

    Carp::croak('An unexpected argument was given to Whostmgr::Accounts::UpgradeOpportunities::get()') if %opts;    # error for cPanel developers only: do not translate or use Cpanel::Exception for this one

    my %user_info;
    _get_bw_limit_info( \%user_info, $nearness_fraction );
    _get_disk_usage_info( \%user_info, $nearness_fraction, $disk_threshold_blocks, $silence_unlimited );

    # TODO: Instead of just providing "reached" (for the hard limit), maybe provide
    # something like "reached_opportunity_threshold", but give it a better name.

    # Provide a clearer visual indication if any data is missing for a user
    for my $u ( values %user_info ) {
        $u->{$_} ||= undef for qw(bw_limit disk_usage);
    }

    return ( \%user_info, \%supplemental );
}

# Private: Add the bandwidth limit info to $user_info_hr. This function returns nothing.
sub _get_bw_limit_info ( $user_info_hr, $nearness_fraction ) {
    my $current_month       = Whostmgr::DateTime::getmonth();
    my $current_year        = Whostmgr::DateTime::getyear();
    my $prev_month          = $current_month == 1          ? 12                : $current_month - 1;
    my $year_for_prev_month = $prev_month > $current_month ? $current_year - 1 : $current_year;

    my $locale = Cpanel::Locale->get_handle;

    for my $month_info (
        [ 'this_month', $current_month, $current_year ],
        [ 'last_month', $prev_month,    $year_for_prev_month ]
    ) {
        my ( $which, $m, $y ) = @$month_info;

        my $bw = Whostmgr::API::1::Utils::Execute::execute_or_die( Bandwidth => 'showbw', { month => $m, year => $y } )->get_raw_data();

        for my $acct_item ( @{ $bw->{acct} } ) {
            my @message_ars = (
                ( $user_info_hr->{ $acct_item->{user} }{messages} ||= [] ),              # user-level
                ( $user_info_hr->{ $acct_item->{user} }{bw_limit}{messages} ||= [] ),    # opportunity-level
            );

            # Consider collapsing this structure some to make it easier for the caller to loop over the response
            my $user_bw_info = ( $user_info_hr->{ $acct_item->{user} }{bw_limit}{$which} ||= {} );

            $user_bw_info->{reached}  = $acct_item->{bwlimited} ? 1 : 0;
            $user_bw_info->{fraction} = 0 + sprintf( '%.2f', _is_unlimited( $acct_item->{limit} ) ? 0 : $acct_item->{totalbytes} / $acct_item->{limit} );
            $user_bw_info->{near}     = $user_bw_info->{fraction} >= $nearness_fraction ? 1 : 0;

            if ( $user_bw_info->{reached} ) {
                if ( $which eq 'this_month' ) {
                    push @$_, $locale->maketext('This account is currently suspended because it has exceeded its bandwidth quota for this month.') for @message_ars;
                }
                else {
                    push @$_, $locale->maketext('This account exceeded its bandwidth quota last month.') for @message_ars;
                }
            }
            elsif ( $user_bw_info->{near} ) {
                if ( $which eq 'this_month' ) {
                    push @$_, $locale->maketext( 'This account has used [_1]% of its bandwidth quota for this month.', $user_bw_info->{fraction} * 100 ) for @message_ars;
                }
                else {
                    push @$_, $locale->maketext( 'This account used [_1]% of its bandwidth quota last month.', $user_bw_info->{fraction} * 100 ) for @message_ars;
                }
            }
        }
    }

    return;
}

sub _get_disk_usage_info ( $user_info_hr, $nearness_fraction, $disk_threshold_blocks, $silence_unlimited ) {    ##no critic(ProhibitManyArgs)
    my $disk_usage = Whostmgr::API::1::Utils::Execute::execute_or_die( DiskUsage => 'get_disk_usage' )->get_raw_data();

    my $locale = Cpanel::Locale->get_handle;

    for my $account ( @{ $disk_usage->{accounts} } ) {
        my $user_disk_info = ( $user_info_hr->{ $account->{user} }{disk_usage} ||= {} );
        my $messages_ar    = ( $user_disk_info->{messages}                     ||= [] );

        my $disk_quota = $account->{blocks_limit};

        for my $limit_type (
            [ 'relative_to_quota',        $disk_quota ],
            [ 'relative_to_fixed_amount', $silence_unlimited && _is_unlimited($disk_quota) ? 0 : $disk_threshold_blocks ],    # to stop tickets
        ) {
            my ( $type, $limit ) = @$limit_type;

            if ( !defined( $account->{blocks_used} ) ) {                                                                      # If initial quota setup has never been done on the server
                @{ $user_disk_info->{$type} }{qw(fraction reached threshold_blocks near)} = ( undef, undef, undef, undef );
            }
            else {
                $user_disk_info->{$type}{fraction}         = 0 + sprintf( '%.2f', _is_unlimited($limit) ? 0 : $account->{blocks_used} / $limit );
                $user_disk_info->{$type}{reached}          = $user_disk_info->{$type}{fraction} >= 1                  ? 1          : 0;
                $user_disk_info->{$type}{threshold_blocks} = $limit                                                   ? 0 + $limit : undef;
                $user_disk_info->{$type}{near}             = $user_disk_info->{$type}{fraction} >= $nearness_fraction ? 1          : 0;

                if ( $user_disk_info->{$type}{reached} ) {
                    if ( $type eq 'relative_to_quota' ) {
                        push @$messages_ar, $locale->maketext('This account has reached its disk quota.');
                    }
                    else {
                        push @$messages_ar, $locale->maketext( 'This account has reached the fixed block count [_1].', $limit );
                    }
                }
                elsif ( $user_disk_info->{$type}{near} ) {
                    if ( $type eq 'relative_to_quota' ) {
                        push @$messages_ar, $locale->maketext( 'This account has used [_1]% of its disk quota.', $user_disk_info->{$type}{fraction} * 100 );
                    }
                    else {
                        push @$messages_ar, $locale->maketext( 'This account has used [_1]% of the block count ([_2]).', $user_disk_info->{$type}{fraction} * 100, $limit );
                    }
                }
            }
        }
        my $user_messages_ar = ( $user_info_hr->{ $account->{user} }{messages} ||= [] );
        push @$user_messages_ar, $_ for @$messages_ar;
    }

    return;
}

sub _is_unlimited ($limit) {
    return ( !$limit || $limit eq 'unlimited' );
}

sub _get_friendly_name_map() {
    my $locale = Cpanel::Locale->get_handle;
    return {
        'opportunity' => {
            'bw_limit'   => $locale->maketext('Bandwidth Limit'),
            'disk_usage' => $locale->maketext('Disk Usage'),
        }
    };
}

1;
